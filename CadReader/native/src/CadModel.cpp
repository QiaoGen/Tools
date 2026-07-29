#include "CadModel.hpp"

extern "C" {
#include <dwg.h>
#include <dwg_api.h>
}

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <limits>
#include <unordered_map>

namespace cad {
namespace {

constexpr double kPi = 3.14159265358979323846;

struct Point { double x = 0; double y = 0; };
struct Transform { double a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0; };

Transform multiply(const Transform& lhs, const Transform& rhs) {
  return {lhs.a * rhs.a + lhs.c * rhs.b, lhs.b * rhs.a + lhs.d * rhs.b,
          lhs.a * rhs.c + lhs.c * rhs.d, lhs.b * rhs.c + lhs.d * rhs.d,
          lhs.a * rhs.tx + lhs.c * rhs.ty + lhs.tx,
          lhs.b * rhs.tx + lhs.d * rhs.ty + lhs.ty};
}
Transform translation(double x, double y) { return {1, 0, 0, 1, x, y}; }
Transform scaling(double x, double y) { return {x, 0, 0, y, 0, 0}; }
Transform rotation(double angle) {
  const double cs = std::cos(angle), sn = std::sin(angle);
  return {cs, sn, -sn, cs, 0, 0};
}
Point apply(const Transform& t, double x, double y) {
  return {t.a * x + t.c * y + t.tx, t.b * x + t.d * y + t.ty};
}

Color aciColor(int index) {
  switch (std::abs(index)) {
    case 1: return {1.0f, 0.30f, 0.28f, 1};
    case 2: return {1.0f, 0.88f, 0.18f, 1};
    case 3: return {0.25f, 1.0f, 0.30f, 1};
    case 4: return {0.22f, 0.90f, 1.0f, 1};
    case 5: return {0.36f, 0.48f, 1.0f, 1};
    case 6: return {1.0f, 0.25f, 0.92f, 1};
    case 7: return {0.93f, 0.96f, 0.94f, 1};
    default: return {0.72f, 0.82f, 0.75f, 1};
  }
}

Color entityColor(const Dwg_Object* object) {
  if (!object || object->supertype != DWG_SUPERTYPE_ENTITY || !object->tio.entity) return aciColor(7);
  const Dwg_Color& source = object->tio.entity->color;
  const unsigned rgb = source.rgb & 0x00ffffffu;
  // LibreDWG stores the color method in the high byte. 0xc3 is an ACI
  // color (the low bytes may merely contain the ACI index), while 0xc2 is
  // an actual RGB color. Treating every non-zero rgb field as truecolor
  // turns common ACI colors such as 7 into almost-black RGB(0,0,7).
  if (source.method == 0xc2 && rgb != 0) {
    return {static_cast<float>((rgb >> 16) & 255) / 255.0f,
            static_cast<float>((rgb >> 8) & 255) / 255.0f,
            static_cast<float>(rgb & 255) / 255.0f, 1};
  }
  return aciColor(source.index > 0 && source.index < 256 ? source.index : 7);
}

std::string cleanText(const char* value) {
  if (!value) return {};
  std::string text(value), result;
  result.reserve(text.size());
  bool command = false;
  for (std::size_t i = 0; i < text.size(); ++i) {
    if (text[i] == '\\' && i + 1 < text.size()) {
      if (text[i + 1] == 'P') { result.push_back(' '); ++i; continue; }
      command = true;
      continue;
    }
    if (command) { if (text[i] == ';') command = false; continue; }
    if (text[i] != '{' && text[i] != '}') result.push_back(text[i]);
  }
  return result;
}

class SceneBuilder {
 public:
  explicit SceneBuilder(Dwg_Data& drawing) : drawing_(drawing), scene_(std::make_shared<Scene>()) {
    for (BITCODE_BL i = 0; i < drawing_.num_objects; ++i) {
      Dwg_Object* object = &drawing_.object[i];
      objectByHandle_[object->handle.value] = object;
      if (object->fixedtype == DWG_TYPE_BLOCK_HEADER)
        blockByHandle_[object->handle.value] = object;
    }
    const auto& extMin = drawing_.header_vars.EXTMIN;
    const auto& extMax = drawing_.header_vars.EXTMAX;
    const double width = extMax.x - extMin.x;
    const double height = extMax.y - extMin.y;
    if (std::isfinite(extMin.x) && std::isfinite(extMin.y) &&
        std::isfinite(extMax.x) && std::isfinite(extMax.y) &&
        width > 1e-9 && height > 1e-9 && width < 1e15 && height < 1e15) {
      const double marginX = width * 0.05;
      const double marginY = height * 0.05;
      clipBounds_ = {extMin.x - marginX, extMin.y - marginY,
                     extMax.x + marginX, extMax.y + marginY, true};
    }
  }

  std::shared_ptr<Scene> build() {
    Dwg_Object* modelObject = nullptr;
    Dwg_Object_BLOCK_HEADER** headers = dwg_getall_BLOCK_HEADER(&drawing_);
    if (headers) {
      for (int i = 0; headers[i]; ++i) {
        if (headers[i]->name && std::strcmp(headers[i]->name, "*Model_Space") == 0 && headers[i]->parent) {
          const BITCODE_BL objectId = headers[i]->parent->objid;
          if (objectId < drawing_.num_objects) modelObject = &drawing_.object[objectId];
          break;
        }
      }
      free(headers);
    }
    if (!modelObject) return nullptr;
    renderOwned(modelObject, {}, 0);
    if (!scene_->bounds.valid) scene_->bounds = {0, 0, 100, 100, true};
    finalizeCoordinates();
    scene_->layerCount = countLayers();
    return scene_;
  }

 private:
  std::size_t countLayers() const {
    std::size_t count = 0;
    for (BITCODE_BL i = 0; i < drawing_.num_objects; ++i)
      if (drawing_.object[i].fixedtype == DWG_TYPE_LAYER) ++count;
    return count;
  }

  void finalizeCoordinates() {
    if (scene_->lineVertices.empty()) {
      scene_->fitBounds = scene_->bounds;
      return;
    }

    Bounds meaningful;
    const auto& extMin = drawing_.header_vars.EXTMIN;
    const auto& extMax = drawing_.header_vars.EXTMAX;
    const double headerWidth = extMax.x - extMin.x;
    const double headerHeight = extMax.y - extMin.y;
    if (std::isfinite(extMin.x) && std::isfinite(extMin.y) &&
        std::isfinite(extMax.x) && std::isfinite(extMax.y) &&
        headerWidth > 1e-9 && headerHeight > 1e-9 &&
        headerWidth < 1e15 && headerHeight < 1e15) {
      // AutoCAD's model-space extents are a much better initial camera than
      // vertex percentiles for drawings with large nested block references.
      meaningful = {extMin.x, extMin.y, extMax.x, extMax.y, true};
    }

    const std::size_t maxSamples = 200000;
    const std::size_t step = std::max<std::size_t>(1, scene_->lineVertices.size() / maxSamples);
    std::vector<float> xs;
    std::vector<float> ys;
    xs.reserve(std::min(maxSamples, scene_->lineVertices.size()));
    ys.reserve(xs.capacity());
    for (std::size_t i = 0; i < scene_->lineVertices.size(); i += step) {
      xs.push_back(scene_->lineVertices[i].x);
      ys.push_back(scene_->lineVertices[i].y);
    }
    std::sort(xs.begin(), xs.end());
    std::sort(ys.begin(), ys.end());
    const std::size_t low = std::min(xs.size() - 1, static_cast<std::size_t>(xs.size() * 0.01));
    const std::size_t high = std::min(xs.size() - 1, static_cast<std::size_t>(xs.size() * 0.99));
    if (!meaningful.valid) {
      meaningful = {xs[low], ys[low], xs[high], ys[high], true};
      if (meaningful.width() <= 1e-9 || meaningful.height() <= 1e-9) meaningful = scene_->bounds;
    }

    const double originX = meaningful.centerX();
    const double originY = meaningful.centerY();
    for (auto& vertex : scene_->lineVertices) {
      vertex.x -= static_cast<float>(originX);
      vertex.y -= static_cast<float>(originY);
    }
    for (auto& label : scene_->labels) {
      label.x -= originX;
      label.y -= originY;
    }
    scene_->bounds.minX -= originX;
    scene_->bounds.maxX -= originX;
    scene_->bounds.minY -= originY;
    scene_->bounds.maxY -= originY;
    meaningful.minX -= originX;
    meaningful.maxX -= originX;
    meaningful.minY -= originY;
    meaningful.maxY -= originY;
    scene_->fitBounds = meaningful;
  }

  void extend(Point p) {
    if (!std::isfinite(p.x) || !std::isfinite(p.y)) return;
    auto& b = scene_->bounds;
    if (!b.valid) { b = {p.x, p.y, p.x, p.y, true}; return; }
    b.minX = std::min(b.minX, p.x); b.minY = std::min(b.minY, p.y);
    b.maxX = std::max(b.maxX, p.x); b.maxY = std::max(b.maxY, p.y);
  }

  void segment(Point from, Point to, Color color) {
    if (scene_->lineVertices.size() >= kMaxVertices) { scene_->truncated = true; return; }
    if (!std::isfinite(from.x) || !std::isfinite(from.y) || !std::isfinite(to.x) || !std::isfinite(to.y)) return;
    if (clipBounds_.valid &&
        ((from.x < clipBounds_.minX && to.x < clipBounds_.minX) ||
         (from.x > clipBounds_.maxX && to.x > clipBounds_.maxX) ||
         (from.y < clipBounds_.minY && to.y < clipBounds_.minY) ||
         (from.y > clipBounds_.maxY && to.y > clipBounds_.maxY))) return;
    scene_->lineVertices.push_back({(float)from.x, (float)from.y, color.r, color.g, color.b, color.a});
    scene_->lineVertices.push_back({(float)to.x, (float)to.y, color.r, color.g, color.b, color.a});
    extend(from); extend(to);
  }

  void arc(const Transform& transform, Point center, double radius, double start, double end, Color color) {
    while (end < start) end += 2 * kPi;
    const double sweep = std::min(end - start, 2 * kPi);
    const int parts = std::clamp((int)std::ceil(std::abs(sweep) / (kPi / 24)), 8, 96);
    Point previous = apply(transform, center.x + radius * std::cos(start), center.y + radius * std::sin(start));
    for (int i = 1; i <= parts; ++i) {
      const double angle = start + sweep * i / parts;
      Point current = apply(transform, center.x + radius * std::cos(angle), center.y + radius * std::sin(angle));
      segment(previous, current, color); previous = current;
    }
  }

  void bulge(const Transform& transform, Point p1, Point p2, double amount, Color color) {
    if (std::abs(amount) < 1e-10) { segment(apply(transform, p1.x, p1.y), apply(transform, p2.x, p2.y), color); return; }
    const double dx = p2.x - p1.x, dy = p2.y - p1.y, chord = std::hypot(dx, dy);
    if (chord < 1e-10) return;
    const double theta = 4 * std::atan(amount);
    const double offset = chord * (1 - amount * amount) / (4 * amount);
    Point center{(p1.x + p2.x) * .5 - dy / chord * offset,
                 (p1.y + p2.y) * .5 + dx / chord * offset};
    const double radius = std::hypot(p1.x - center.x, p1.y - center.y);
    const double start = std::atan2(p1.y - center.y, p1.x - center.x);
    const int parts = std::clamp((int)std::ceil(std::abs(theta) / (kPi / 24)), 4, 96);
    Point previous = apply(transform, p1.x, p1.y);
    for (int i = 1; i <= parts; ++i) {
      const double angle = start + theta * i / parts;
      Point current = apply(transform, center.x + radius * std::cos(angle), center.y + radius * std::sin(angle));
      segment(previous, current, color); previous = current;
    }
  }

  void renderOwned(Dwg_Object* header, const Transform& transform, int depth) {
    if (!header || depth > 16) return;
    if (header->fixedtype != DWG_TYPE_BLOCK_HEADER || !header->tio.object || !header->tio.object->tio.BLOCK_HEADER) return;
    if (std::find(blockStack_.begin(), blockStack_.end(), header->handle.value) != blockStack_.end()) return;
    blockStack_.push_back(header->handle.value);
    auto* block = header->tio.object->tio.BLOCK_HEADER;
    const BITCODE_BL count = std::min<BITCODE_BL>(block->num_owned, 5000000);
    const int passes = depth == 0 ? 3 : 2;
    bool stopped = false;
    for (int pass = 0; pass < passes && !stopped; ++pass) {
      for (BITCODE_BL i = 0; i < count; ++i) {
        if (scene_->lineVertices.size() >= std::min(kMaxVertices, rootVertexLimit_) ||
            scene_->entityCount >= std::min(kMaxEntities, rootEntityLimit_)) {
          scene_->truncated = true;
          stopped = true;
          break;
        }
        Dwg_Object_Ref* reference = block->entities ? block->entities[i] : nullptr;
        if (!reference) continue;
        Dwg_Object* object = reference->obj;
        if (!object) {
          const auto found = objectByHandle_.find(reference->absolute_ref);
          if (found != objectByHandle_.end()) object = found->second;
        }
        if (!object) continue;
        const bool isInsert = object->fixedtype == DWG_TYPE_INSERT || object->fixedtype == DWG_TYPE_MINSERT;
        if (depth == 0) {
          int priority = 0;
          if (isInsert) {
            double x = 0, y = 0;
            if (object->fixedtype == DWG_TYPE_INSERT) {
              x = object->tio.entity->tio.INSERT->ins_pt.x;
              y = object->tio.entity->tio.INSERT->ins_pt.y;
            } else {
              x = object->tio.entity->tio.MINSERT->ins_pt.x;
              y = object->tio.entity->tio.MINSERT->ins_pt.y;
            }
            const bool nearModel = !clipBounds_.valid ||
                (x >= clipBounds_.minX && x <= clipBounds_.maxX &&
                 y >= clipBounds_.minY && y <= clipBounds_.maxY);
            priority = nearModel ? 1 : 2;
          }
          if (priority != pass) continue;
        } else if ((isInsert ? 1 : 0) != pass) {
          continue;
        }
        if (depth == 0 && isInsert) {
          rootEntityLimit_ = std::min(kMaxEntities, scene_->entityCount + kMaxEntitiesPerRootInsert);
          rootVertexLimit_ = std::min(kMaxVertices, scene_->lineVertices.size() + kMaxVerticesPerRootInsert);
          renderObject(object, transform, depth);
          rootEntityLimit_ = std::numeric_limits<std::size_t>::max();
          rootVertexLimit_ = std::numeric_limits<std::size_t>::max();
        } else {
          renderObject(object, transform, depth);
        }
      }
    }
    blockStack_.pop_back();
  }

  Dwg_Object* resolveBlock(Dwg_Object_Ref* reference) const {
    if (!reference) return nullptr;
    if (reference->obj && reference->obj->fixedtype == DWG_TYPE_BLOCK_HEADER) return reference->obj;
    const auto found = blockByHandle_.find(reference->absolute_ref);
    if (found != blockByHandle_.end()) return found->second;
    return nullptr;
  }

  void renderObject(Dwg_Object* object, const Transform& transform, int depth) {
    if (!object || object->supertype != DWG_SUPERTYPE_ENTITY || !object->tio.entity || object->tio.entity->invisible) return;
    ++scene_->entityCount;
    const Color color = entityColor(object);
    auto* entity = object->tio.entity;

    switch (object->fixedtype) {
      case DWG_TYPE_LINE: {
        auto* line = entity->tio.LINE;
        segment(apply(transform, line->start.x, line->start.y), apply(transform, line->end.x, line->end.y), color);
        break;
      }
      case DWG_TYPE_CIRCLE: {
        auto* circle = entity->tio.CIRCLE;
        arc(transform, {circle->center.x, circle->center.y}, circle->radius, 0, 2 * kPi, color);
        break;
      }
      case DWG_TYPE_ARC: {
        auto* value = entity->tio.ARC;
        arc(transform, {value->center.x, value->center.y}, value->radius, value->start_angle, value->end_angle, color);
        break;
      }
      case DWG_TYPE_ELLIPSE: {
        auto* value = entity->tio.ELLIPSE;
        const int parts = 64;
        Point previous{}; bool hasPrevious = false;
        double end = value->end_angle; while (end < value->start_angle) end += 2 * kPi;
        for (int i = 0; i <= parts; ++i) {
          const double t = value->start_angle + (end - value->start_angle) * i / parts;
          Point current = apply(transform,
              value->center.x + value->sm_axis.x * std::cos(t) - value->sm_axis.y * value->axis_ratio * std::sin(t),
              value->center.y + value->sm_axis.y * std::cos(t) + value->sm_axis.x * value->axis_ratio * std::sin(t));
          if (hasPrevious) segment(previous, current, color);
          previous = current; hasPrevious = true;
        }
        break;
      }
      case DWG_TYPE_LWPOLYLINE: {
        auto* line = entity->tio.LWPOLYLINE;
        for (BITCODE_BL i = 1; i < line->num_points; ++i) {
          const double b = i - 1 < line->num_bulges ? line->bulges[i - 1] : 0;
          bulge(transform, {line->points[i - 1].x, line->points[i - 1].y}, {line->points[i].x, line->points[i].y}, b, color);
        }
        if ((line->flag & 512) && line->num_points > 2) {
          const BITCODE_BL last = line->num_points - 1;
          const double b = last < line->num_bulges ? line->bulges[last] : 0;
          bulge(transform, {line->points[last].x, line->points[last].y}, {line->points[0].x, line->points[0].y}, b, color);
        }
        break;
      }
      case DWG_TYPE_POLYLINE_2D: {
        auto* line = entity->tio.POLYLINE_2D;
        Point first{}, previous{}; double previousBulge = 0; bool has = false;
        for (BITCODE_BL i = 0; i < line->num_owned; ++i) {
          Dwg_Object* vertexObject = line->vertex && line->vertex[i] ? line->vertex[i]->obj : nullptr;
          if (!vertexObject || vertexObject->fixedtype != DWG_TYPE_VERTEX_2D) continue;
          auto* vertex = vertexObject->tio.entity->tio.VERTEX_2D;
          Point current{vertex->point.x, vertex->point.y};
          if (!has) { first = current; has = true; } else bulge(transform, previous, current, previousBulge, color);
          previous = current; previousBulge = vertex->bulge;
        }
        if (has && (line->flag & 1)) bulge(transform, previous, first, previousBulge, color);
        break;
      }
      case DWG_TYPE_SPLINE: {
        auto* spline = entity->tio.SPLINE;
        if (spline->num_fit_pts > 1 && spline->fit_pts) {
          for (BITCODE_BS i = 1; i < spline->num_fit_pts; ++i)
            segment(apply(transform, spline->fit_pts[i - 1].x, spline->fit_pts[i - 1].y),
                    apply(transform, spline->fit_pts[i].x, spline->fit_pts[i].y), color);
        } else if (spline->num_ctrl_pts > 1 && spline->ctrl_pts) {
          for (BITCODE_BL i = 1; i < spline->num_ctrl_pts; ++i)
            segment(apply(transform, spline->ctrl_pts[i - 1].x, spline->ctrl_pts[i - 1].y),
                    apply(transform, spline->ctrl_pts[i].x, spline->ctrl_pts[i].y), color);
        }
        break;
      }
      case DWG_TYPE_TEXT: {
        auto* text = entity->tio.TEXT;
        Point p = apply(transform, text->ins_pt.x, text->ins_pt.y);
        if (clipBounds_.valid && (p.x < clipBounds_.minX || p.x > clipBounds_.maxX ||
                                  p.y < clipBounds_.minY || p.y > clipBounds_.maxY)) break;
        scene_->labels.push_back({p.x, p.y, std::max(.1, text->height), text->rotation + std::atan2(transform.b, transform.a), color, cleanText(text->text_value)});
        extend(p);
        break;
      }
      case DWG_TYPE_MTEXT: {
        auto* text = entity->tio.MTEXT;
        Point p = apply(transform, text->ins_pt.x, text->ins_pt.y);
        if (clipBounds_.valid && (p.x < clipBounds_.minX || p.x > clipBounds_.maxX ||
                                  p.y < clipBounds_.minY || p.y > clipBounds_.maxY)) break;
        const double angle = std::atan2(text->x_axis_dir.y, text->x_axis_dir.x) + std::atan2(transform.b, transform.a);
        scene_->labels.push_back({p.x, p.y, std::max(.1, text->text_height), angle, color, cleanText(text->text)});
        extend(p);
        break;
      }
      case DWG_TYPE_INSERT: {
        auto* insert = entity->tio.INSERT;
        auto* blockObject = resolveBlock(insert->block_header);
        if (!blockObject) break;
        auto* block = blockObject->tio.object ? blockObject->tio.object->tio.BLOCK_HEADER : nullptr;
        const double baseX = block ? block->base_pt.x : 0, baseY = block ? block->base_pt.y : 0;
        Transform local = multiply(translation(insert->ins_pt.x, insert->ins_pt.y), rotation(insert->rotation));
        local = multiply(local, scaling(insert->scale.x, insert->scale.y));
        local = multiply(local, translation(-baseX, -baseY));
        renderOwned(blockObject, multiply(transform, local), depth + 1);
        break;
      }
      case DWG_TYPE_MINSERT: {
        auto* insert = entity->tio.MINSERT;
        auto* blockObject = resolveBlock(insert->block_header);
        if (!blockObject) break;
        auto* block = blockObject->tio.object ? blockObject->tio.object->tio.BLOCK_HEADER : nullptr;
        const double baseX = block ? block->base_pt.x : 0, baseY = block ? block->base_pt.y : 0;
        for (int row = 0; row < std::max(1, (int)insert->num_rows); ++row)
          for (int col = 0; col < std::max(1, (int)insert->num_cols); ++col) {
            Transform local = multiply(translation(insert->ins_pt.x + col * insert->col_spacing,
                                                   insert->ins_pt.y + row * insert->row_spacing), rotation(insert->rotation));
            local = multiply(local, scaling(insert->scale.x, insert->scale.y));
            local = multiply(local, translation(-baseX, -baseY));
            renderOwned(blockObject, multiply(transform, local), depth + 1);
          }
        break;
      }
      default: break;
    }
  }

  Dwg_Data& drawing_;
  std::shared_ptr<Scene> scene_;
  static constexpr std::size_t kMaxVertices = 8'000'000;
  static constexpr std::size_t kMaxEntities = 3'000'000;
  static constexpr std::size_t kMaxEntitiesPerRootInsert = 5'000;
  static constexpr std::size_t kMaxVerticesPerRootInsert = 20'000;
  std::unordered_map<BITCODE_RLL, Dwg_Object*> blockByHandle_;
  std::unordered_map<BITCODE_RLL, Dwg_Object*> objectByHandle_;
  std::vector<BITCODE_RLL> blockStack_;
  Bounds clipBounds_;
  std::size_t rootEntityLimit_ = std::numeric_limits<std::size_t>::max();
  std::size_t rootVertexLimit_ = std::numeric_limits<std::size_t>::max();
};

}  // namespace

LoadResult loadDrawing(const std::string& path) {
  const auto started = std::chrono::steady_clock::now();
  LoadResult result;
  if (!std::filesystem::exists(path)) { result.error = "文件不存在"; return result; }

  Dwg_Data drawing;
  std::memset(&drawing, 0, sizeof(drawing));
  drawing.opts = 0;
  const int error = dwg_read_file(path.c_str(), &drawing);
  if (error & ~(DWG_ERR_CRITICAL - 1)) {
    result.error = "LibreDWG 读取失败，错误码 " + std::to_string(error);
    dwg_free(&drawing);
    return result;
  }

  SceneBuilder builder(drawing);
  result.scene = builder.build();
  if (!result.scene) result.error = "图纸中没有可读取的模型空间";
  else result.scene->sourceName = std::filesystem::path(path).filename().string();
  result.elapsedSeconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
  dwg_free(&drawing);
  return result;
}

}  // namespace cad
