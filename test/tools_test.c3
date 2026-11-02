module c3pkg_test;
import c3pkg::tools, c3pkg::http;

fn void names_and_versions() @test
{
	assert(tools::is_name("my-lib_2"));
	assert(!tools::is_name(""));
	assert(!tools::is_name("../x"));
	assert(!tools::is_name("1.0"));
	assert(tools::is_version("1.0.0-rc.1+b2"));
	assert(!tools::is_version(".."));
	assert(!tools::is_version("."));
	assert(!tools::is_version("1/0"));
}

fn void paths() @test
{
	assert(tools::is_safe_path("lib"));
	assert(tools::is_safe_path("a/b"));
	assert(!tools::is_safe_path(""));
	assert(!tools::is_safe_path("/etc"));
	assert(!tools::is_safe_path("\\\\host\\x"));
	assert(!tools::is_safe_path("a/../b"));
	assert(!tools::is_safe_path(".."));
	assert(tools::is_safe_path("a..b"));
	assert(!tools::is_safe_path("C:x"));
}

fn void escape() @test
{
	assert(http::escape("a b&c") == "a%20b%26c");
	assert(http::escape("json-1.0_x~") == "json-1.0_x~");
	assert(http::escape("") == "");
}

fn void truncation() @test
{
	assert(tools::truncate("short") == "short");
	char[] big = mem::talloc_array(char, 40000);
	foreach (&c : big) *c = 'a';
	assert(tools::truncate((String)big).len < 30100);
	// 2-byte characters: the cut must not land inside one
	big[0] = 'a';
	foreach (i, &c : big) if (i > 0) *c = i % 2 == 1 ? 0xC3 : 0xA9;
	String t = tools::truncate((String)big);
	assert(t.starts_with((String)big[:29999]));
	assert(t[29999] == '\n');
}

fn void failures() @test
{
	assert(tools::failure({ 200, "ok" }) == "");
	assert(tools::failure({ 404, "x" }).starts_with("HTTP 404"));
	assert(tools::failure({ 302, "" }).starts_with("HTTP 302"));
	assert(tools::failure({ 0, "boom" }) == "request failed: boom");
}
