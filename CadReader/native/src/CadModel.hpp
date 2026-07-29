#pragma once

#include <array>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace cad {

struct Color {
  float r = 0.88f;
  float g = 0.92f;
  float b = 0.89f;
  float a = 1.0f;
};

struct Vertex {
  float x = 0;
  float y = 0;
  float r = 1;
  float g = 1;
  float b = 1;
  float a = 1;
};

struct TextLabel {
  double x = 0;
  double y = 0;
  double height = 1;
  double angle = 0;
  Color color;
  std::string text;
};

struct Bounds {
  double minX = 0;
  double minY = 0;
  double maxX = 1;
  double maxY = 1;
  bool valid = false;

  double width() const { return maxX - minX; }
  double height() const { return maxY - minY; }
  double centerX() const { return (minX + maxX) * 0.5; }
  double centerY() const { return (minY + maxY) * 0.5; }
};

struct Scene {
  std::vector<Vertex> lineVertices;
  std::vector<TextLabel> labels;
  Bounds bounds;
  Bounds fitBounds;
  std::size_t entityCount = 0;
  std::size_t layerCount = 0;
  bool truncated = false;
  std::string sourceName;
};

struct LoadResult {
  std::shared_ptr<Scene> scene;
  std::string error;
  double elapsedSeconds = 0;
};

LoadResult loadDrawing(const std::string& path);

}  // namespace cad
