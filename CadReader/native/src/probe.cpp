#include "CadModel.hpp"

#include <iostream>

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "Usage: CadReaderProbe drawing.dwg\n";
    return 2;
  }
  cad::LoadResult result = cad::loadDrawing(argv[1]);
  if (!result.scene) {
    std::cerr << "ERROR: " << result.error << "\n";
    return 1;
  }
  std::cout << "OK elapsed=" << result.elapsedSeconds
            << " entities=" << result.scene->entityCount
            << " vertices=" << result.scene->lineVertices.size()
            << " labels=" << result.scene->labels.size()
            << " layers=" << result.scene->layerCount
            << " truncated=" << result.scene->truncated << "\n";
  return 0;
}
