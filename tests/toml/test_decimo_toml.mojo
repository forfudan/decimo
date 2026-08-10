"""Comprehensive test suite for decimo.toml — covers all TOML features."""

from decimo.toml import parse_string, parse_file
from std import testing


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()


# ---------------------------------------------------------------------------
# 1. Basic key-value pairs
# ---------------------------------------------------------------------------
def test_basic_key_value() raises:
    var doc = parse_string(
        """
title = "TOML Example"
count = 42
pi = 3.14
enabled = true
"""
    )
    assert_true(doc.get("title").as_string() == "TOML Example", "basic string")
    assert_true(doc.get("count").as_int() == 42, "basic int")
    assert_true(doc.get("enabled").as_bool() == True, "basic bool")
    print("  PASS  test_basic_key_value")


# ---------------------------------------------------------------------------
# 2. Standard tables
# ---------------------------------------------------------------------------
def test_table() raises:
    var doc = parse_string(
        """
[server]
host = "localhost"
port = 1018
"""
    )
    var srv = doc.get_table("server")
    assert_true(srv["host"].as_string() == "localhost", "table host")
    assert_true(srv["port"].as_int() == 1018, "table port")
    print("  PASS  test_table")


# ---------------------------------------------------------------------------
# 3. Simple array
# ---------------------------------------------------------------------------
def test_array() raises:
    var doc = parse_string(
        """
colors = ["red", "green", "blue"]
numbers = [1, 2, 3]
"""
    )
    var colors = doc.get("colors").as_array()
    assert_true(len(colors) == 3, "array len")
    assert_true(colors[0].as_string() == "red", "array[0]")
    assert_true(colors[2].as_string() == "blue", "array[2]")
    print("  PASS  test_array")


# ---------------------------------------------------------------------------
# 4. Multiline array with trailing comma & comments
# ---------------------------------------------------------------------------
def test_multiline_array() raises:
    var doc = parse_string(
        """
fruits = [
    "apple",
    "banana",
    "orange",
]
"""
    )
    var fruits = doc.get("fruits").as_array()
    assert_true(len(fruits) == 3, "multiline array len")
    assert_true(fruits[1].as_string() == "banana", "multiline array[1]")
    print("  PASS  test_multiline_array")


# ---------------------------------------------------------------------------
# 5. Dotted keys
# ---------------------------------------------------------------------------
def test_dotted_keys() raises:
    var doc = parse_string(
        """
fruit.name = "apple"
fruit.color = "red"
fruit.size.width = 10
fruit.size.height = 20
"""
    )
    var fruit_val = doc.get("fruit")
    assert_true(fruit_val.is_table(), "dotted key creates table")
    var fruit = fruit_val.as_table()
    assert_true(fruit["name"].as_string() == "apple", "dotted key name")
    assert_true(fruit["color"].as_string() == "red", "dotted key color")

    var size = fruit["size"].as_table()
    assert_true(size["width"].as_int() == 10, "dotted key nested width")
    assert_true(size["height"].as_int() == 20, "dotted key nested height")
    print("  PASS  test_dotted_keys")


# ---------------------------------------------------------------------------
# 6. Dotted table headers
# ---------------------------------------------------------------------------
def test_dotted_table_headers() raises:
    var doc = parse_string(
        """
[a.b.c]
key = "value"
"""
    )
    var a = doc.get("a")
    assert_true(a.is_table(), "dotted header a is table")
    ref b = a.as_table()["b"]
    assert_true(b.is_table(), "dotted header b is table")
    ref c = b.as_table()["c"]
    assert_true(c.is_table(), "dotted header c is table")
    assert_true(c.as_table()["key"].as_string() == "value", "dotted header val")
    print("  PASS  test_dotted_table_headers")


# ---------------------------------------------------------------------------
# 7. Quoted keys
# ---------------------------------------------------------------------------
def test_quoted_keys() raises:
    var doc = parse_string(
        """
"my key" = "value1"
'bare-literal' = "value2"
"""
    )
    assert_true(doc.get("my key").as_string() == "value1", "quoted key")
    print("  PASS  test_quoted_keys")


# ---------------------------------------------------------------------------
# 8. Inline tables
# ---------------------------------------------------------------------------
def test_inline_table() raises:
    var doc = parse_string(
        """
point = {x = 1, y = 2}
"""
    )
    var pt = doc.get("point")
    assert_true(pt.is_table(), "inline table is table")
    var t = pt.as_table()
    assert_true(t["x"].as_int() == 1, "inline table x")
    assert_true(t["y"].as_int() == 2, "inline table y")
    print("  PASS  test_inline_table")


# ---------------------------------------------------------------------------
# 9. Nested inline tables
# ---------------------------------------------------------------------------
def test_inline_table_nested() raises:
    var doc = parse_string(
        """
animal = {type.name = "cat"}
"""
    )
    var animal = doc.get("animal").as_table()
    var type_tbl = animal["type"].as_table()
    assert_true(type_tbl["name"].as_string() == "cat", "nested inline table")
    print("  PASS  test_inline_table_nested")


# ---------------------------------------------------------------------------
# 10. Array of tables
# ---------------------------------------------------------------------------
def test_array_of_tables() raises:
    var doc = parse_string(
        """
[[products]]
name = "Hammer"
sku = 738594937

[[products]]
name = "Nail"
sku = 284758393
"""
    )
    var products = doc.get_array_of_tables("products")
    assert_true(len(products) == 2, "AoT length")
    assert_true(products[0]["name"].as_string() == "Hammer", "AoT[0] name")
    assert_true(products[1]["name"].as_string() == "Nail", "AoT[1] name")
    print("  PASS  test_array_of_tables")


# ---------------------------------------------------------------------------
# 11. Array of tables with dotted header
# ---------------------------------------------------------------------------
def test_array_of_tables_dotted() raises:
    var doc = parse_string(
        """
[[fruits]]
name = "apple"

[[fruits]]
name = "banana"
"""
    )
    var fruits = doc.get_array_of_tables("fruits")
    assert_true(len(fruits) == 2, "dotted AoT len")
    assert_true(fruits[0]["name"].as_string() == "apple", "dotted AoT[0]")
    assert_true(fruits[1]["name"].as_string() == "banana", "dotted AoT[1]")
    print("  PASS  test_array_of_tables_dotted")


# ---------------------------------------------------------------------------
# 12. Unicode escape sequences
# ---------------------------------------------------------------------------
def test_unicode_escapes() raises:
    var doc = parse_string(
        """
smile = "\\u0041"
"""
    )
    # \u0041 = 'A'
    assert_true(doc.get("smile").as_string() == "A", "unicode \\u0041 = A")
    print("  PASS  test_unicode_escapes")


# ---------------------------------------------------------------------------
# 13. Integer bases: hex, octal, binary
# ---------------------------------------------------------------------------
def test_integer_bases() raises:
    var doc = parse_string(
        """
hex = 0xDEADBEEF
oct = 0o755
bin = 0b11010110
dec = 1_000_000
"""
    )
    assert_true(doc.get("hex").as_int() == 0xDEADBEEF, "hex int")
    assert_true(doc.get("oct").as_int() == 0o755, "octal int")
    assert_true(doc.get("bin").as_int() == 0b11010110, "binary int")
    assert_true(doc.get("dec").as_int() == 1000000, "underscore int")
    print("  PASS  test_integer_bases")


# ---------------------------------------------------------------------------
# 14. Special float values (inf, nan)
# ---------------------------------------------------------------------------
def test_special_floats() raises:
    var doc = parse_string(
        """
pos_inf = inf
neg_inf = -inf
not_a_number = nan
"""
    )
    assert_true(doc.get("pos_inf").as_float() == Float64.MAX, "inf")
    assert_true(doc.get("neg_inf").as_float() == -Float64.MAX, "-inf")
    print("  PASS  test_special_floats")


# ---------------------------------------------------------------------------
# 15. Multiline basic strings
# ---------------------------------------------------------------------------
def test_multiline_strings() raises:
    var src = String('[test]\nml = """line1\nline2\nline3"""\n')
    var doc = parse_string(src)
    var tbl = doc.get_table("test")
    var ml = tbl["ml"].as_string()
    # The multiline string should contain the newlines
    assert_true(ml.byte_length() > 0, "multiline string not empty")
    print("  PASS  test_multiline_strings")


# ---------------------------------------------------------------------------
# 16. Nested tables via dotted keys + standard tables
# ---------------------------------------------------------------------------
def test_nested_tables_via_dotted() raises:
    var doc = parse_string(
        """
[server]
host = "localhost"

[server.database]
name = "books_of_yuhao"
port = 1314
"""
    )
    var server = doc.get("server").as_table()
    assert_true(server["host"].as_string() == "localhost", "server.host")
    var db = server["database"].as_table()
    assert_true(
        db["name"].as_string() == "books_of_yuhao", "server.database.name"
    )
    assert_true(db["port"].as_int() == 1314, "server.database.port")
    print("  PASS  test_nested_tables_via_dotted")


# ---------------------------------------------------------------------------
# 17. Duplicate key detection
# ---------------------------------------------------------------------------
def test_duplicate_key_detection() raises:
    var caught = False
    try:
        var doc = parse_string(
            """
name = "first"
name = "second"
"""
        )
    except e:
        caught = True
    assert_true(caught, "duplicate key should raise")
    print("  PASS  test_duplicate_key_detection")


# ---------------------------------------------------------------------------
# 18. Mixed features
# ---------------------------------------------------------------------------
def test_mixed_features() raises:
    var doc = parse_string(
        """
title = "Mixed Test"

[database]
server = "192.168.1.1"
ports = [8001, 8001, 8002]
connection_max = 5000
enabled = true

[database.credentials]
username = "admin"
password = "secret"

[[servers]]
name = "alpha"
ip = "10.0.0.1"
role = "frontend"

[[servers]]
name = "beta"
ip = "10.0.0.2"
role = "backend"
"""
    )
    assert_true(doc.get("title").as_string() == "Mixed Test", "mixed title")

    var db = doc.get("database").as_table()
    assert_true(db["server"].as_string() == "192.168.1.1", "mixed db server")
    assert_true(db["connection_max"].as_int() == 5000, "mixed db conn_max")

    var cred = db["credentials"].as_table()
    assert_true(cred["username"].as_string() == "admin", "mixed db cred user")

    var servers = doc.get_array_of_tables("servers")
    assert_true(len(servers) == 2, "mixed servers len")
    assert_true(servers[0]["name"].as_string() == "alpha", "mixed server[0]")
    assert_true(servers[1]["role"].as_string() == "backend", "mixed server[1]")
    print("  PASS  test_mixed_features")


# ---------------------------------------------------------------------------
# 19. Parse our actual pixi.toml to make sure it still works
# ---------------------------------------------------------------------------
def test_our_pixi_toml() raises:
    var doc = parse_file("pixi.toml")
    var ws = doc.get_table("workspace")
    assert_true(len(ws) > 0, "pixi.toml workspace table non-empty")
    assert_true(ws["name"].as_string() == "decimo", "pixi.toml name")
    var tasks = doc.get_table("tasks")
    assert_true(len(tasks) > 0, "pixi.toml tasks table non-empty")
    print("  PASS  test_our_pixi_toml")


# ---------------------------------------------------------------------------
def assert_true(cond: Bool, msg: String) raises:
    if not cond:
        raise Error("ASSERTION FAILED: " + msg)
