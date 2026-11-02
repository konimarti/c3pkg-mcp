module c3pkg::http;
import curl;

const usz MAX_BODY = 64 * 1024 * 1024;
const String HEX = "0123456789ABCDEF";

<* status 0 means the request itself failed; `body` then holds the reason. *>
struct Response
{
	int status;
	String body;
}

String base_url = "https://www.c3pkg.eu";
String token;

struct Sink
{
	DString buf;
	bool overflow;
}

fn usz on_write(char* ptr, usz size, usz nmemb, void* userdata) @private
{
	Sink* sink = userdata;
	usz n = size * nmemb;
	if ((usz)sink.buf.len() + n > MAX_BODY)
	{
		sink.overflow = true;
		return 0;
	}
	sink.buf.append(ptr[:n]);
	return n;
}

<*
 Perform a request against the registry. `form` is a flat list of name, value pairs sent as
 multipart/form-data together with `file` (if not empty). Redirects are not followed.
 Everything is allocated on the temp allocator.
*>
fn Response request(String method, String path, String[] form = {}, String file = "")
{
	Curl* h = curl::easy_init();
	if (!h) return { 0, "cannot initialise curl" };
	defer curl::easy_cleanup(h);

	Sink sink;
	sink.buf.tinit();
	char[256] err;
	CurlSlist* headers = curl::slist_append(null, "User-Agent: c3pkg-mcp");
	defer curl::slist_free_all(headers);
	if (token.len) headers = curl::slist_append(headers, string::tformat("Authorization: Bearer %s", token).zstr_tcopy());

	curl::easy_setopt(h, CurlOption.URL, string::tformat("%s%s", base_url, path).zstr_tcopy());
	curl::easy_setopt(h, CurlOption.CUSTOMREQUEST, method.zstr_tcopy());
	curl::easy_setopt(h, CurlOption.HTTPHEADER, headers);
	curl::easy_setopt(h, CurlOption.WRITEFUNCTION, &on_write);
	curl::easy_setopt(h, CurlOption.WRITEDATA, &sink);
	curl::easy_setopt(h, CurlOption.ERRORBUFFER, &err);
	curl::easy_setopt(h, CurlOption.NOSIGNAL, 1L);
	curl::easy_setopt(h, CurlOption.CONNECTTIMEOUT, 15L);
	curl::easy_setopt(h, CurlOption.TIMEOUT, 120L);

	CurlMime* mime;
	defer if (mime) curl::mime_free(mime);
	if (form.len || file.len)
	{
		mime = curl::mime_init(h);
		for (usz i = 0; i + 1 < form.len; i += 2)
		{
			if (!form[i + 1].len) continue;
			CurlMimePart* p = curl::mime_addpart(mime);
			curl::mime_name(p, form[i].zstr_tcopy());
			curl::mime_data(p, form[i + 1].ptr, form[i + 1].len);
		}
		if (file.len)
		{
			CurlMimePart* p = curl::mime_addpart(mime);
			curl::mime_name(p, "file");
			if (curl::mime_filedata(p, file.zstr_tcopy()) != CurlResult.OK) return { 0, string::tformat("cannot read %s", file) };
		}
		curl::easy_setopt(h, CurlOption.MIMEPOST, mime);
	}

	CurlResult res = curl::easy_perform(h);
	if (sink.overflow) return { 0, "response too large" };
	if (res != CurlResult.OK)
	{
		String why = ((ZString)&err).str_view();
		return { 0, why.len ? why.tcopy() : ((ZString)curl::easy_strerror(res)).str_view().tcopy() };
	}
	CLong status;
	curl::easy_getinfo(h, CurlInfoType.RESPONSE_CODE, &status);
	return { (int)status, sink.buf.str_view() };
}

<* Percent-encode a URL query value. *>
fn String escape(String s)
{
	DString out;
	out.tinit();
	foreach (c : s)
	{
		if (c.is_alnum() || c == '-' || c == '_' || c == '.' || c == '~')
		{
			out.append_char(c);
			continue;
		}
		out.append_char('%');
		out.append_char(HEX[c >> 4]);
		out.append_char(HEX[c & 15]);
	}
	return out.str_view();
}
