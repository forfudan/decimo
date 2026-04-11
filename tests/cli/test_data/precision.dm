# High-precision stress test - expressions that need many digits to
# distinguish correct answers from off-by-one rounding errors.

# 1/7 has a 6-digit repeating cycle
1/7

# pi subtracted from a close rational approximation
pi - 355/113

# sqrt(2) * sqrt(2) should be exactly 2
sqrt(2) * sqrt(2)

# e^(pi*sqrt(163)) is close to an integer (Ramanujan's constant)
exp(pi * sqrt(163))

# Cancellation stress: nearly equal values
exp(1) - (1 + 1 + 1/2 + 1/6 + 1/24 + 1/120 + 1/720)
