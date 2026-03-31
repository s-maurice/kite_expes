#pragma once
#include <cmath>
#include <cstdint>
#include "RandomGenerator.hpp"

class ZipfianGenerator {
public:
  uint64_t n;
  double theta, alpha, zetan, eta, zeta2;

  ZipfianGenerator(uint64_t n, double theta) : n(n), theta(theta) {
    if (theta == 1.0) {
      theta = 0.999;
    }
    zeta2 = zeta(2, theta);
    alpha = 1.0 / (1.0 - theta);
    zetan = zeta(n, theta);
    eta = (1.0 - std::pow(2.0 / n, 1.0 - theta)) / (1.0 - zeta2 / zetan);
  }

  double zeta(uint64_t n, double theta) {
    if (n < 1000) {
        double sum = 0;
        for (uint64_t i = 1; i <= n; i++) sum += 1.0 / std::pow(i, theta);
        return sum;
    } else {
        double sum = 0;
        for (uint64_t i = 1; i <= 1000; i++) sum += 1.0 / std::pow(i, theta);
        // Integral from 1000 to n
        double approx = (std::pow(n, 1.0 - theta) - std::pow(1000.0, 1.0 - theta)) / (1.0 - theta);
        approx += 0.5 * (1.0 / std::pow(1000.0, theta) + 1.0 / std::pow(n, theta));
        return sum + approx;
    }
  }

  uint64_t getNext() {
    double u = static_cast<double>(RandomGenerator::getRanduint64_t() % 10000000000ULL) / 10000000000.0;
    double uz = u * zetan;
    if (uz < 1.0) return 0;
    if (uz < 1.0 + std::pow(0.5, theta)) return 1;
    uint64_t ret = static_cast<uint64_t>(n * std::pow(eta * u - eta + 1.0, alpha));
    if (ret >= n) ret = n - 1;
    return ret;
  }
};
