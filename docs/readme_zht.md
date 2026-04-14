# Decimo（原名 DeciMojo） <!-- omit from toc -->

由 [Mojo 程序設計語言 🔥](https://www.modular.com/mojo) 實現的任意精度整數和小數運算庫，靈感來源自 Python 的 `int` 和 `Decimal`。

**[English](https://zhuyuhao.com/decimo/)**　|　**[更新日誌](https://github.com/forfudan/decimo/blob/main/docs/changelog.md)**　|　**[GitHub 倉庫»](https://github.com/forfudan/decimo)**　|　**[Discord 頻道»](https://discord.gg/3rGH87uZTk)**

- [概述](#概述)
- [安裝](#安裝)
- [快速開始](#快速開始)
- [目標](#目標)
- [狀態](#狀態)
- [測試與基準](#測試與基準)
- [引用](#引用)
- [許可證](#許可證)

## 概述

Decimo 爲 Mojo 提供任意精度整數和小數運算庫，爲金融建模、科學計算以及浮點近似誤差不可接受的應用提供精確計算。除了基本算術運算外，該庫還包括具有保證精度的高級數學函數。

對於 Python 用戶，`decimo.BInt` 之於 Mojo 就如同 `int` 之於 Python，`decimo.Decimal` 之於 Mojo 就如同 `decimal.Decimal` 之於 Python。

核心類型包括:

- 任意精度有符號整數類型 `BInt`[^bigint]，是 Python `int` 的 Mojo 原生等價實現。
- 任意精度小數實現 (`Decimal`)，允許進行無限位數和小數位的計算[^arbitrary]，是 Python `decimal.Decimal` 的 Mojo 原生等價實現。
- 128 位定點小數實現 (`Dec128`)，支持最多 29 位有效數字，小數點後最多 28 位數字[^fixed]。

| 類型      | 別名                 | 信息                               | 內部表示     |
| --------- | -------------------- | ---------------------------------- | ------------ |
| `BInt`    | `BigInt`             | 等價於 Python 的 `int`             | Base-2^32    |
| `Decimal` | `BigDecimal`, `BDec` | 等價於 Python 的 `decimal.Decimal` | Base-10^9    |
| `Dec128`  | `Decimal128`         | 128 位定點精度小數類型             | 三個 32 位字 |

輔助類型包括基於 10 進制的任意精度有符號整數類型 (`BigInt10`) 和任意精度無符號整數類型 (`BigUInt`)，支持無限位數[^bigint10]。`BigUInt` 是 `BigInt10` 和 `Decimal` 的內部表示。

---

> 得此魔咒者，即脱凡相，識天數，斬三尸，二十七日飛升。
> —— 《太上靈通感應二十七章經》

Decimo 是 Decimal 和 Mojo 的組合，既反映了它的目的，也反應了它的設計語言。Decimo本身也是拉丁語的詞，意爲「第十」，即「十進制」一詞的詞源。

---

此倉庫包含內建的 [TOML 解析器](./docs/readme_toml.md)（`decimo.toml`），一個純 Mojo 實現的輕量級 TOML v1.0 解析器。它解析配置文件和測試數據，支持基本類型、數組和嵌套表。雖然爲 Decimo 的測試框架而創建，但它提供通用的結構化數據解析，具有簡潔的 API。

## 安裝

Decimo 可在 modular-community `https://repo.prefix.dev/modular-community` 包倉庫中獲取。爲了訪問此倉庫，請將其添加到您的 `pixi.toml` 文件中的 `channels` 列表：

```toml
channels = ["https://conda.modular.com/max", "https://repo.prefix.dev/modular-community", "conda-forge"]
```

接下來，您可以使用以下任一方法進行安裝：

1. 從 `pixi` CLI，運行命令 ```pixi add decimo```。這會獲取最新版本並使其立即可用於導入。

1. 在您項目的 `mojoproject.toml` 文件中，添加以下依賴：

    ```toml
    decimo = "==0.9.0"
    ```

    然後運行 `pixi install` 來下載並安裝包。

1. 對於 `main` 分支中的最新開發版本，請克隆 [此 GitHub 倉庫](https://github.com/forfudan/decimo) 並使用命令 `pixi run package` 在本地構建包。

下表總結了包版本及其對應的 Mojo 版本：

| 包名       | 版本   | Mojo 版本     | 包管理器 |
| ---------- | ------ | ------------- | -------- |
| `decimojo` | v0.1.0 | ==25.1        | magic    |
| `decimojo` | v0.2.0 | ==25.2        | magic    |
| `decimojo` | v0.3.0 | ==25.2        | magic    |
| `decimojo` | v0.3.1 | >=25.2, <25.4 | pixi     |
| `decimojo` | v0.4.x | ==25.4        | pixi     |
| `decimojo` | v0.5.0 | ==25.5        | pixi     |
| `decimojo` | v0.6.0 | ==0.25.7      | pixi     |
| `decimojo` | v0.7.0 | ==0.26.1      | pixi     |
| `decimo`   | v0.8.0 | ==0.26.1      | pixi     |
| `decimo`   | v0.9.0 | ==0.26.2      | pixi     |

## 快速開始

您可以通過導入 `decimo` 模塊開始使用 Decimo。一個簡單的方法是從 `prelude` 模塊導入所有內容，它提供最常用的類型。

```mojo
from decimo import *
```

這將導入以下類型或別名到您的命名空間：

- `BInt`（`BigInt` 的別名）：任意精度有符號整數類型，等價於 Python 的 `int`。
- `Decimal`（也可用 `BigDecimal` 或 `BDec`）：任意精度小數類型，等價於 Python 的 `decimal.Decimal`。
- `Dec128`（`Decimal128` 的別名）：128 位定點精度小數類型。
- `RoundingMode`：捨入模式的枚舉。
- `ROUND_DOWN`、`ROUND_HALF_UP`、`ROUND_HALF_EVEN`、`ROUND_UP`：常用捨入模式的常量。

---

以下是一些展示 `Decimal` 類型任意精度特性的例子。對於某些數學運算，默認精度（有效數字位數）設為 `28`。您可以通過向函數傳遞 `precision` 參數來更改精度。當 Mojo 支持全局變量時，此默認精度將可以全局配置。

```mojo
from decimo.prelude import *


fn main() raises:
    var a = Decimal("123456789.123456789")
    var b = Decimal(
        "1234.56789"
    )

    # === 基本算術 === #
    print(a + b)  # 123458023.691346789
    print(a - b)  # 123455554.555566789
    print(a * b)  # 152415787654.32099750190521
    print(a.true_divide(b + 1))  # 99919.06565608207008357913866

    # === 指數函數 === #
    print(a.sqrt(precision=80))
    # 11111.111066111110969430554981749302328338130654689094538188579359566416821203641
    print(a.cbrt(precision=80))
    # 497.93385938415242742001134219007635925452951248903093962731782327785111102410518
    print(a.root(b, precision=80))
    # 1.0152058862996527138602610522640944903320735973237537866713119992581006582644107
    print(a.power(b, precision=80))
    # 3.3463611024190802340238135400789468682196324482030786573104956727660098625641520E+9989
    print(a.exp(precision=80))
    # 1.8612755889649587035842377856492201091251654136588338983610243887893287518637652E+53616602
    print(a.log(b, precision=80))
    # 2.6173300266565482999078843564152939771708486260101032293924082259819624360226238
    print(a.ln(precision=80))
    # 18.631401767168018032693933348296537542797015174553735308351756611901741276655161

    # === 三角函數 === #
    print(a.sin(precision=200))
    # 0.99985093087193092464780008002600992896256609588456
    #   91036188395766389946401881352599352354527727927177
    #   79589259132243649550891532070326452232864052771477
    #   31418817041042336608522984511928095747763538486886
    print(b.cos(precision=1000))
    # -0.9969577603867772005841841569997528013669868536239849713029893885930748434064450375775817720425329394
    #    9756020177557431933434791661179643984869397089102223199519409695771607230176923201147218218258755323
    #    7563476302904118661729889931783126826250691820526961290122532541861737355873869924820906724540889765
    #    5940445990824482174517106016800118438405307801022739336016834311018727787337447844118359555063575166
    #    5092352912854884589824773945355279792977596081915868398143592738704592059567683083454055626123436523
    #    6998108941189617922049864138929932713499431655377552668020889456390832876383147018828166124313166286
    #    6004871998201597316078894718748251490628361253685772937806895692619597915005978762245497623003811386
    #    0913693867838452088431084666963414694032898497700907783878500297536425463212578556546527017688874265
    #    0785862902484462361413598747384083001036443681873292719322642381945064144026145428927304407689433744
    #    5821277763016669042385158254006302666602333649775547203560187716156055524418512492782302125286330865

    # === 數字的內部表示 === #
    (
        Decimal(
            "3.141592653589793238462643383279502884197169399375105820974944"
        ).power(2, precision=60)
    ).print_internal_representation()
    # Internal Representation Details of BigDecimal
    # ----------------------------------------------
    # number:         9.8696044010893586188344909998
    #                 761511353136994072407906264133
    #                 5
    # coefficient:    986960440108935861883449099987
    #                 615113531369940724079062641335
    # negative:       False
    # scale:          59
    # word 0:         62641335
    # word 1:         940724079
    # word 2:         113531369
    # word 3:         99987615
    # word 4:         861883449
    # word 5:         440108935
    # word 6:         986960
    # ----------------------------------------------
```

---

以下是展示 `BInt` 類型（`BigInt` 的別名）每個主要功能的綜合快速入門指南。

```mojo
from decimo.prelude import *


fn main() raises:
    # === 構造 ===
    var a = BInt("12345678901234567890")  # 從字符串
    var b = BInt(12345)  # 從整數
    var c = BInt("1991_10,18")  # 從帶分隔符的字符串
    print(a, b, c)

    # === 基本算術 ===
    print(a + b)  # 加法: 12345678901234580235
    print(a - b)  # 減法: 12345678901234555545
    print(a * b)  # 乘法: 152415787814108380241050

    # === 除法運算 ===
    print(a // b)  # 向下整除: 999650944609516
    print(a.truncate_divide(b))  # 截斷除法: 999650944609516
    print(a % b)  # 取模: 9615

    # === 冪運算 ===
    print(BInt(2).power(10))  # 冪: 1024
    print(BInt(2) ** 10)  # 冪（使用 ** 運算符）: 1024

    # === 比較 ===
    print(a > b)  # 大於: True
    print(a == BInt("12345678901234567890"))  # 相等: True
    print(a.is_zero())  # 檢查是否爲零: False

    # === 類型轉換 ===
    print(String(a))  # 轉換爲字符串: "12345678901234567890"

    # === 符號處理 ===
    print(-a)  # 取負: -12345678901234567890
    print(
        abs(BInt("-12345678901234567890"))
    )  # 絕對值: 12345678901234567890
    print(a.is_negative())  # 檢查是否爲負: False

    # === 超大數字 ===
    # 3600 位數 // 1800 位數
    print(BInt("123456789" * 400) // BInt("987654321" * 200))

    # === 最大公因數 ===
    print(a.gcd(b))  # 最大公因數: 15
    print(a.gcd(c))  # 最大公因數: 6
```

---

以下是展示 `Decimal128` 類型（`Dec128`）每個主要功能的綜合快速入門指南。

```mojo
from decimo.prelude import *

fn main() raises:
    # === 構造 ===
    var a = Dec128("123.45")                         # 從字符串
    var b = Dec128(123)                              # 從整數
    var c = Dec128(123, 2)                           # 帶精度的整數 (1.23)
    var d = Dec128.from_float(3.14159)               # 從浮點數
    
    # === 基本算術 ===
    print(a + b)                                     # 加法: 246.45
    print(a - b)                                     # 減法: 0.45
    print(a * b)                                     # 乘法: 15184.35
    print(a / b)                                     # 除法: 1.0036585365853658536585365854
    
    # === 捨入與精度 ===
    print(a.round(1))                                # 捨入到 1 位小數: 123.5
    print(a.quantize(Dec128("0.01")))                # 格式化到 2 位小數: 123.45
    print(a.round(0, RoundingMode.ROUND_DOWN))       # 向下捨入到整數: 123
    
    # === 比較 ===
    print(a > b)                                     # 大於: True
    print(a == Dec128("123.45"))                     # 相等: True
    print(a.is_zero())                               # 檢查是否爲零: False
    print(Dec128("0").is_zero())                     # 檢查是否爲零: True
    
    # === 類型轉換 ===
    print(Float64(a))                                # 轉換爲浮點數: 123.45
    print(a.to_int())                                # 轉換爲整數: 123
    print(a.to_str())                                # 轉換爲字符串: "123.45"
    print(a.coefficient())                           # 獲取係數: 12345
    print(a.scale())                                 # 獲取精度: 2
    
    # === 數學函數 ===
    print(Dec128("2").sqrt())                        # 平方根: 1.4142135623730950488016887242
    print(Dec128("100").root(3))                     # 立方根: 4.641588833612778892410076351
    print(Dec128("2.71828").ln())                    # 自然對數: 0.9999993273472820031578910056
    print(Dec128("10").log10())                      # 以 10 爲底的對數: 1
    print(Dec128("16").log(Dec128("2")))             # 以 2 爲底的對數: 3.9999999999999999999999999999
    print(Dec128("10").exp())                        # e^10: 22026.465794806716516957900645
    print(Dec128("2").power(10))                     # 冪: 1024
    
    # === 符號處理 ===
    print(-a)                                        # 取負: -123.45
    print(abs(Dec128("-123.45")))                    # 絕對值: 123.45
    print(Dec128("123.45").is_negative())            # 檢查是否爲負: False
    
    # === 特殊值 ===
    print(Dec128.PI())                               # π 常數: 3.1415926535897932384626433833
    print(Dec128.E())                                # e 常數: 2.7182818284590452353602874714
    print(Dec128.ONE())                              # 值 1: 1
    print(Dec128.ZERO())                             # 值 0: 0
    print(Dec128.MAX())                              # 最大值: 79228162514264337593543950335
    
    # === 便利方法 ===
    print(Dec128("123.400").is_integer())            # 檢查是否爲整數: False
    print(a.number_of_significant_digits())          # 計算有效數字位數: 5
    print(Dec128("12.34").to_str_scientific())       # 科學計數法: 1.234E+1
```

## 目標

金融計算和數據分析需要精確的小數算術，而浮點數無法可靠地提供這種精確性。作爲一名從事金融學研究和信用風險模型驗證工作的人員，在將個人項目從 Python 遷移到 Mojo 時，我需要一個可靠的、能够正確捨入的、固定精度的數值類型。

由於 Mojo 目前在其標準庫中缺乏原生的 Decimal 類型，我決定創建自己的實現來填補這一空白。

本項目從多個已建立的小數實現和文檔中汲取靈感，例如 [Python 内置的 `Decimal` 類型](https://docs.python.org/3/library/decimal.html)，[Rust 的 `rust_decimal` crate](https://docs.rs/rust_decimal/latest/rust_decimal/index.html)，[Microsoft 的 `Decimal` 實現](https://learn.microsoft.com/en-us/dotnet/api/system.decimal.getbits?view=net-9.0&redirectedfrom=MSDN#System_Decimal_GetBits_System_Decimal_)，[通用小數算術規範](https://speleotrove.com/decimal/decarith.html) 等。非常感謝前輩們的貢獻及其對開放知識共享的促進。

## 狀態

羅馬不是一日建成的。Decimo 目前正在積極開發中。它已成功通過 **"讓它工作"** 階段和 **"讓它正確"** 階段，現已深入 **"讓它快速"** 階段。

`BInt` 類型已經完全實現並優化。它已經與 Python 的 `int` 進行了基準測試，並在大多數情況下表現出優越的性能。

歡迎錯誤報告和功能請求！如果您遇到問題，請[在此提交](https://github.com/forfudan/decimo/issues)。

## 測試與基準

在將倉庫克隆到本地磁盤後，您可以：

- 使用 `pixi run test` 運行測試。
- 使用 `pixi run bench` 運行基準測試。

## 引用

如果您發現 Decimo 對您的研究有用，請考慮將它加入您的引用中。

```tex
@software{Zhu.2026,
    author       = {Zhu, Yuhao},
    year         = {2026},
    title        = {Decimo: An arbitrary-precision integer and decimal library for Mojo},
    url          = {https://github.com/forfudan/decimo},
    version      = {0.9.0},
    note         = {Computer Software}
}
```

## 許可證

本倉庫及其所有貢獻内容均採用 Apache 許可證 2.0 版本授權。

[^fixed]: `Decimal128` 類型可以表示最多 29 位有效數字，小數點後最多 28 位數字的值。當數值超過最大可表示值（`2^96 - 1`）時，Decimo 會拋出錯誤或將數值捨入以符合這些約束。例如，`8.8888888888888888888888888888`（總共 29 個 8，小數點後 28 位）的有效數字超過了最大可表示值（`2^96 - 1`），會自動捨入爲 `8.888888888888888888888888889`（總共 28 個 8，小數點後 27 位）。Decimo 的 `Decimal128` 類型類似於 `System.Decimal`（C#/.NET）、Rust 中的 `rust_decimal`、SQL Server 中的 `DECIMAL/NUMERIC` 等。
[^bigint]: `BigInt` 使用 base-2^32 表示，採用小端格式，最低有效字存儲在索引 0。每個字是一個 `UInt32`，允許對大整數進行高效存儲和算術運算。這種設計優化了二進制計算的性能，同時支持任意精度。
[^bigint10]: BigInt10 使用基於 10 的表示（保持十進制語義），而內部使用優化的基於 10^9 的存儲系統進行高效計算。這種方法在人類可讀的十進制操作與高性能計算之間取得平衡。它提供向下整除（向負無窮舍入）和截斷除法（向零舍入）語義，無論操作數符號如何，都能確保除法操作具有正確的數學行爲。
[^arbitrary]: 建立在已完成的 BigInt10 實現之上，Decimal 支持整數和小數部分的任意精度，類似於 Python 中的 `decimal` 和 `mpmath`、Java 中的 `java.math.BigDecimal` 等。
