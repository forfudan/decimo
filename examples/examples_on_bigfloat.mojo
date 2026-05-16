from decimo import BigFloat


def main() raises:
    var a = BigFloat("123456789.123456789", precision=28)
    var b = BigFloat("1234.56789", precision=28)

    # === Basic Arithmetic === #
    print(a + b)  # 123458023.691346789
    print(a - b)  # 123455554.555566789
    print(a * b)  # 152415787654.32099750190521
    print(a / (b + BigFloat("1")))  # 99919.0656560820708357913866

    # === Exponential Functions === #
    print(a.sqrt())  # 11111.11106611111096943055498
    print(a.exp())  # 1.861275588964958703584237786e+53616602
    print(a.ln())  # 18.63140176716801803269393335

    # === Trigonometric Functions === #
    print(a.sin())  # 0.99985093087193092464780008
    print(b.cos())  # -0.996957760386777200584184157
