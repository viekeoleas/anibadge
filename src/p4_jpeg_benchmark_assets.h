#pragma once

#include <stddef.h>
#include <stdint.h>

namespace p4jpegbenchmark {

struct BenchmarkAsset {
  const char *name;
  const char *content_class;
  const uint8_t *data;
  size_t size;
};

extern const BenchmarkAsset kBenchmarkAssets[];
extern const size_t kBenchmarkAssetCount;

}  // namespace p4jpegbenchmark
