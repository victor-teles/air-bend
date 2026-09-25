import Base
import ./air/lib/text.bend as Text
import ./air/lib/chunk.bend as Chunk
import ./air/lib/json.bend as Json
import ./air/lib/http.bend as Http
import ./air/lib/form.bend as Form
import ./air/lib/negotiate.bend as Negotiate
import ./air/lib/disk.bend as Disk
import ./air/lib/static.bend as Static
import ./air/lib/errors.bend as Errors
import ./air/lib/random.bend as Random
import ./air/lib/log.bend as Log
import ./air/lib/store.bend as Store
import ./air/lib/rate.bend as Rate
import ./air/lib/session.bend as Session
import ./air/lib/schema.bend as Schema
import ./air/lib/view.bend as View
import ./air/lib/cors.bend as Cors
import ./air/lib/shield.bend as Shield
import ./air/lib/router.bend as Router
import ./air/lib/race.bend as Race
import ./air/lib/drain.bend as Drain
import ./air/lib/server.bend as Server
import ./air/lib/test.bend as Test
import ./air/lib/config.bend as Config
import ./air/lib/hooks.bend as Hooks
import ./air/lib/health.bend as Health
import ./air/lib/openapi.bend as OpenApi
import ./air/lib/metrics.bend as Metrics
import ./air/lib/trace.bend as Trace

# Routing
# -------

law segments_drop_empty:
  {Text.segments("/users//42/") == ["users", "42"] : List<&2, String>}

# A handler that does nothing, for laws about route lists.
def noop(req: Http.Request) -> IO(Http.Response):
  IO.pure(Http.Response, Http.Response.empty(204))

law classify_segments:
  {[Router.classify("users"), Router.classify(":id"), Router.classify("*rest")]
    == [Router.Lit{"users"}, Router.Param{"id"}, Router.Rest{"rest"}]
    : List<&2, Router.Seg>}

law route_binds_param:
  {Router.match_path([Router.Lit{"users"}, Router.Param{"id"}], ["users", "42"], Some{Map.new(&2, String)})
    == Some{Map.set(&2, String, Map.new(&2, String), "id", "42")}
    : Maybe<&2, Map<&2, String>>}

law route_rejects_literal:
  {Router.match_path([Router.Lit{"users"}, Router.Param{"id"}], ["posts", "42"], Some{Map.new(&2, String)})
    == None{}
    : Maybe<&2, Map<&2, String>>}

law route_rejects_length:
  {Router.match_path([Router.Lit{"users"}], ["users", "42"], Some{Map.new(&2, String)})
    == None{}
    : Maybe<&2, Map<&2, String>>}

law wildcard_binds_tail:
  {Router.match_path([Router.Lit{"files"}, Router.Rest{"p"}], ["files", "a", "b"], Some{Map.new(&2, String)})
    == Some{Map.set(&2, String, Map.new(&2, String), "p", "a/b")}
    : Maybe<&2, Map<&2, String>>}

law wildcard_binds_empty:
  {Router.match_path([Router.Lit{"files"}, Router.Rest{"p"}], ["files"], Some{Map.new(&2, String)})
    == Some{Map.set(&2, String, Map.new(&2, String), "p", "")}
    : Maybe<&2, Map<&2, String>>}

law shape_anonymizes:
  {Router.shape([Router.Lit{"users"}, Router.Param{"id"}, Router.Rest{"r"}]) == "/users/:/*" : String}

law shape_root:
  {Router.shape([]) == "/" : String}

law mount_prefixes:
  {Router.pattern_of(Router.mount("/api", [Router.get("/users/:id", noop)]))
    == [[Router.Lit{"api"}, Router.Lit{"users"}, Router.Param{"id"}]]
    : List<&2, List<&2, Router.Seg>>}

law all_keeps_order:
  {Router.pattern_of(Router.all([[Router.get("/a", noop)], [Router.get("/b", noop)]]))
    == [[Router.Lit{"a"}], [Router.Lit{"b"}]]
    : List<&2, List<&2, Router.Seg>>}

law conflicts_finds_duplicate:
  {Router.conflicts([Router.get("/users/:id", noop), Router.get("/users/:name", noop)])
    == ["duplicate route: GET /users/:"]
    : List<&2, String>}

law conflicts_keeps_slash_apart:
  {Router.conflicts([Router.get("/s", noop), Router.get("/s/", noop)])
    == []
    : List<&2, String>}

law conflicts_allows_methods:
  {Router.conflicts([Router.get("/users", noop), Router.post("/users", noop)])
    == []
    : List<&2, String>}

law conflicts_flags_wildcard_position:
  {Router.conflicts([Router.get("/a/*x/b", noop)])
    == ["wildcard not last: GET /a/*/b"]
    : List<&2, String>}

law has_slash_root:
  {[Router.has_slash("/"), Router.has_slash("/a"), Router.has_slash("/a/")] == [False{}, False{}, True{}] : List<&2, Bool>}

law strict_slash_gate:
  {[Router.slash_ok(False{}, True{}, False{}), Router.slash_ok(True{}, True{}, False{}), Router.slash_ok(True{}, True{}, True{})]
    == [True{}, False{}, True{}]
    : List<&2, Bool>}

law redirect_target_keeps_query:
  {Router.redirect_target("/users/?page=2") == "/users?page=2" : String}

law redirect_target_drops_all_slashes:
  {Router.redirect_target("/users//") == "/users" : String}

law redirect_target_no_query:
  {Router.redirect_target("/a%20b/") == "/a%20b" : String}

# Methods
# -------

# A request from its head, for laws; a refused head reads as `GET /`.
def request.fin(p: Http.Parsed) -> Http.Request:
  match p:
    case Http.Parsed{req}:
      req
    case Http.Refused{status}:
      Http.Request{Http.GET{}, "HTTP/1.1", "/", "/", Map.new(&2, String), Map.new(&2, String), Map.new(&2, String), "", Map.new(&2, String), None{}}

def request(head: String) -> Http.Request:
  request.fin(Http.Request.parse(Http.Limits.default(), head))

law head_falls_back_to_get:
  {Router.describe(Router.pick(Router.Ignore{}, [Router.get("/", noop)], request("HEAD / HTTP/1.1\r")))
    == "fallback" : String}

law explicit_head_wins:
  {Router.describe(Router.pick(Router.Ignore{}, [Router.get("/", noop), Router.head("/", noop)], request("HEAD / HTTP/1.1\r")))
    == "hit" : String}

law head_needs_a_path_match:
  {Router.describe(Router.pick(Router.Ignore{}, [Router.get("/a", noop)], request("HEAD /b HTTP/1.1\r")))
    == "none" : String}

law allow_lists_methods:
  {Router.describe(Router.pick(Router.Ignore{}, [Router.get("/x", noop), Router.post("/x", noop)], request("DELETE /x HTTP/1.1\r")))
    == "miss: GET, HEAD, OPTIONS, POST" : String}

law allow_without_get_has_no_head:
  {Router.describe(Router.pick(Router.Ignore{}, [Router.post("/x", noop)], request("DELETE /x HTTP/1.1\r")))
    == "miss: OPTIONS, POST" : String}

law miss_unknown_path:
  {Router.describe(Router.pick(Router.Ignore{}, [Router.get("/x", noop)], request("DELETE /y HTTP/1.1\r")))
    == "none" : String}

law options_star_lists_everything:
  {Router.describe(Router.pick(Router.Ignore{}, [Router.get("/a", noop), Router.post("/b", noop)], request("OPTIONS * HTTP/1.1\r")))
    == "miss: GET, HEAD, OPTIONS, POST" : String}

law options_route_is_a_hit:
  {Router.describe(Router.pick(Router.Ignore{}, [Router.get("/a", noop), Router.options("/a", noop)], request("OPTIONS /a HTTP/1.1\r")))
    == "hit" : String}

law allow_header_set:
  {Http.Response.header(Http.Response.method_not_allowed("GET, OPTIONS"), "allow") == "GET, OPTIONS" : String}

law render_options:
  {Http.Response.render(Http.Response.options("GET, OPTIONS"), False{}, True{})
    == "HTTP/1.1 204 No Content\r\nallow: GET, OPTIONS\r\nconnection: keep-alive\r\n\r\n"
    : String}

# HTTP
# ----

law method_roundtrip:
  {Http.Method.show(Http.Method.parse("DELETE")) == "DELETE" : String}

law reason_ok:
  {Http.Status.reason(200) == "OK" : String}

law reason_unknown:
  {Http.Status.reason(299) == "Unknown" : String}

law byte_length_utf8:
  {Text.byte_length("Olá", 0) == 4 : U32}

law split_head:
  {Text.split_str("a\r\n\r\nb", "\r\n\r\n") == Some{("a", "b")} : Maybe<&2, Text.Two()>}

# Paths
# -----

law decode_plain:
  {Text.percent_decode("a%20b", False{}) == Some{"a b"} : Maybe<&2, String>}

law decode_utf8:
  {Text.percent_decode("Ol%C3%A1", False{}) == Some{"Olá"} : Maybe<&2, String>}

law decode_plus_in_query:
  {Text.percent_decode("a+b", True{}) == Some{"a b"} : Maybe<&2, String>}

law decode_plus_in_path:
  {Text.percent_decode("a+b", False{}) == Some{"a+b"} : Maybe<&2, String>}

law decode_rejects_short:
  {Text.percent_decode("a%2", False{}) == None{} : Maybe<&2, String>}

law decode_rejects_bad_hex:
  {Text.percent_decode("%zz", False{}) == None{} : Maybe<&2, String>}

law decode_rejects_nul:
  {Text.percent_decode("%00", False{}) == None{} : Maybe<&2, String>}

law decode_rejects_overlong:
  {Text.percent_decode("%C0%80", False{}) == None{} : Maybe<&2, String>}

law decode_rejects_lone_lead:
  {Text.percent_decode("%C3", False{}) == None{} : Maybe<&2, String>}

law needs_decode_scan:
  {[Text.needs_decode("abc", False{}), Text.needs_decode("a%2", False{}), Text.needs_decode("a+b", False{}), Text.needs_decode("a+b", True{})]
    == [False{}, True{}, False{}, True{}]
    : List<&2, Bool>}

law last_is_scan:
  {[Text.last_is("", '/'), Text.last_is("/", '/'), Text.last_is("/a", '/'), Text.last_is("/a/", '/')]
    == [False{}, True{}, False{}, True{}]
    : List<&2, Bool>}

law decode_rejects_surrogate:
  {Text.percent_decode("%ED%A0%80", False{}) == None{} : Maybe<&2, String>}

law path_decoded:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "GET /hello/Ol%C3%A1 HTTP/1.1\r"))
    == "/hello/Olá" : String}

law path_keeps_encoded_slash:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "GET /a%2Fb HTTP/1.1\r"))
    == "/a/b" : String}

law path_collapses_slashes:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "GET //a///b/ HTTP/1.1\r"))
    == "/a/b/" : String}

law path_resolves_dots:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "GET /a/./b/../c HTTP/1.1\r"))
    == "/a/c" : String}

law path_root:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "GET / HTTP/1.1\r"))
    == "/" : String}

law path_rejects_climb:
  {Http.Parsed.framing(Http.Request.parse(Http.Limits.default(), "GET /../etc HTTP/1.1\r"))
    == Http.Unframed{400} : Http.Framing}

law path_rejects_bad_escape:
  {Http.Parsed.framing(Http.Request.parse(Http.Limits.default(), "GET /a%G1 HTTP/1.1\r"))
    == Http.Unframed{400} : Http.Framing}

law path_absolute_form:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "GET http://h.example/x/y?q=1 HTTP/1.1\r"))
    == "/x/y" : String}

law path_asterisk:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "OPTIONS * HTTP/1.1\r"))
    == "*" : String}

law query_decoded:
  {Http.Parsed.query(Http.Request.parse(Http.Limits.default(), "GET /s?q=caf%C3%A9+au+lait HTTP/1.1\r"), "q")
    == "café au lait" : String}

law query_rejects_bad_escape:
  {Http.Parsed.framing(Http.Request.parse(Http.Limits.default(), "GET /s?q=%ZZ HTTP/1.1\r"))
    == Http.Unframed{400} : Http.Framing}

# Framing
# -------

law digits_strict:
  {Text.digits("5, 5") == None{} : Maybe<&2, U32>}

law digits_empty:
  {Text.digits("") == None{} : Maybe<&2, U32>}

law digits_value:
  {Text.digits("1024") == Some{1024} : Maybe<&2, U32>}

law hex_value:
  {Text.hex("1A") == Some{26} : Maybe<&2, U32>}

law take_bytes_utf8:
  {Text.take_bytes("héllo", 3) == Text.Took{"hé", "llo"} : Text.Take}

law take_bytes_short:
  {Text.take_bytes("hé", 5) == Text.TakeNeed{} : Text.Take}

law take_bytes_split_char:
  {Text.take_bytes("hé", 2) == Text.TakeBad{} : Text.Take}

law chunked_decodes:
  {Chunk.drain(100n, 1000, Chunk.ChunkSize{"4\r\nWiki\r\n5;ext=1\r\npedia\r\n0\r\nx-trailer: 1\r\n\r\nNEXT", "", 0})
    == Chunk.ChunkDone{"Wikipedia", "NEXT"}
    : Chunk.Decoder}

law chunked_waits:
  {Chunk.drain(100n, 1000, Chunk.ChunkSize{"4\r\nWi", "", 0})
    == Chunk.ChunkWait{Chunk.ChunkData{"Wi", "", 0, 4}}
    : Chunk.Decoder}

law chunked_too_large:
  {Chunk.drain(100n, 3, Chunk.ChunkSize{"4\r\nWiki\r\n", "", 0})
    == Chunk.ChunkBad{413}
    : Chunk.Decoder}

law framing_fixed:
  {Http.Parsed.framing(Http.Request.parse(Http.Limits.default(), "POST /a HTTP/1.1\r\nContent-Length: 4\r"))
    == Http.Fixed{4}
    : Http.Framing}

law framing_chunked:
  {Http.Parsed.framing(Http.Request.parse(Http.Limits.default(), "POST /a HTTP/1.1\r\nTransfer-Encoding: Chunked\r"))
    == Http.Chunked{}
    : Http.Framing}

law framing_rejects_both:
  {Http.Parsed.framing(Http.Request.parse(Http.Limits.default(), "POST /a HTTP/1.1\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r"))
    == Http.Unframed{400}
    : Http.Framing}

law framing_rejects_duplicate_length:
  {Http.Parsed.framing(Http.Request.parse(Http.Limits.default(), "POST /a HTTP/1.1\r\nContent-Length: 4\r\nContent-Length: 4\r"))
    == Http.Unframed{400}
    : Http.Framing}

law framing_rejects_folded_header:
  {Http.Parsed.framing(Http.Request.parse(Http.Limits.default(), "GET /a HTTP/1.1\r\nHost: x\r\n  y\r"))
    == Http.Unframed{400}
    : Http.Framing}

law parse_rejects_long_url:
  {Http.Parsed.framing(Http.Request.parse(Http.Limits{100, 100, 3, 100}, "GET /abcd HTTP/1.1\r"))
    == Http.Unframed{414}
    : Http.Framing}

law parse_rejects_version:
  {Http.Parsed.framing(Http.Request.parse(Http.Limits.default(), "GET / HTTP/2.0\r"))
    == Http.Unframed{505}
    : Http.Framing}

# Connections
# -----------

law keep_alive_default_11:
  {Http.Parsed.keep_alive(Http.Request.parse(Http.Limits.default(), "GET / HTTP/1.1\r")) == True{} : Bool}

law keep_alive_close_11:
  {Http.Parsed.keep_alive(Http.Request.parse(Http.Limits.default(), "GET / HTTP/1.1\r\nConnection: close\r")) == False{} : Bool}

law keep_alive_default_10:
  {Http.Parsed.keep_alive(Http.Request.parse(Http.Limits.default(), "GET / HTTP/1.0\r")) == False{} : Bool}

law keep_alive_opt_in_10:
  {Http.Parsed.keep_alive(Http.Request.parse(Http.Limits.default(), "GET / HTTP/1.0\r\nConnection: keep-alive\r")) == True{} : Bool}

law no_body_statuses:
  {[Http.Response.no_body(100), Http.Response.no_body(200), Http.Response.no_body(204), Http.Response.no_body(304)]
    == [True{}, False{}, True{}, True{}]
    : List<&2, Bool>}

law render_head_only:
  {Http.Response.render(Http.Response.text("hi"), True{}, True{})
    == "HTTP/1.1 200 OK\r\nconnection: keep-alive\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 2\r\n\r\n"
    : String}

law render_204_has_no_length:
  {Http.Response.render(Http.Response.empty(204), False{}, False{})
    == "HTTP/1.1 204 No Content\r\nconnection: close\r\n\r\n"
    : String}

# JSON
# ----

law json_parse_object:
  {Json.parse("{\"a\": [1, true, null, \"x\"]}")
    == Some{Json.Obj{[("a", Json.Arr{[Json.Num{"1"}, Json.Boolean{True{}}, Json.Null{}, Json.Str{"x"}]})]}}
    : Maybe<&2, Json.Value>}

law json_parse_empty_containers:
  {Json.parse(" { \"a\" : [ ] , \"b\" : { } } ")
    == Some{Json.Obj{[("a", Json.Arr{[]}), ("b", Json.Obj{[]})]}}
    : Maybe<&2, Json.Value>}

law json_render_escapes:
  {Json.render(Json.Str{"a\"b\\c\n\u{1}"}) == "\"a\\\"b\\\\c\\n\\u0001\"" : String}

law json_render_nested:
  {Json.render(Json.Obj{[("k", Json.Arr{[Json.Num{"1"}, Json.Null{}, Json.Boolean{False{}}]})]}) == "{\"k\":[1,null,false]}" : String}

law json_parse_unicode_escape:
  {Json.parse("\"\\u00e9\"") == Some{Json.Str{"é"}} : Maybe<&2, Json.Value>}

law json_parse_surrogate_pair:
  {Json.parse("\"\\ud83d\\ude00\"") == Some{Json.Str{"😀"}} : Maybe<&2, Json.Value>}

law json_rejects_lone_surrogate:
  {Json.parse("\"\\ud83d\"") == None{} : Maybe<&2, Json.Value>}

law json_rejects_raw_control:
  {Json.parse("\"a\tb\"") == None{} : Maybe<&2, Json.Value>}

law json_rejects_trailing_comma:
  {[Json.parse("[1,]"), Json.parse("{\"a\":1,}")] == [None{}, None{}] : List<&2, Maybe<&2, Json.Value>>}

law json_rejects_mismatched_bracket:
  {Json.parse("[}") == None{} : Maybe<&2, Json.Value>}

law json_rejects_trailing_garbage:
  {Json.parse("{} x") == None{} : Maybe<&2, Json.Value>}

law json_rejects_depth:
  {Json.parse(String.repeat("[", 65n) ++ String.repeat("]", 65n)) == None{} : Maybe<&2, Json.Value>}

law json_accepts_depth_64:
  {Maybe.is_some(&2, Json.Value, Json.parse(String.repeat("[", 64n) ++ String.repeat("]", 64n))) == True{} : Bool}

law json_number_lexeme:
  {Json.parse("-1.5e3") == Some{Json.Num{"-1.5e3"}} : Maybe<&2, Json.Value>}

law json_rejects_bad_numbers:
  {[Json.parse("01"), Json.parse("1."), Json.parse("-"), Json.parse("+1"), Json.parse("1e")]
    == [None{}, None{}, None{}, None{}, None{}] : List<&2, Maybe<&2, Json.Value>>}

law json_rejects_bad_literal:
  {Json.parse("tru") == None{} : Maybe<&2, Json.Value>}

law json_get_first_key:
  {Json.get(Json.Obj{[("a", Json.Num{"1"}), ("a", Json.Num{"2"})]}, "a") == Some{Json.Num{"1"}} : Maybe<&2, Json.Value>}

law json_u32_strict:
  {[Json.u32(Json.Num{"42"}), Json.u32(Json.Num{"-1"}), Json.u32(Json.Str{"42"})] == [Some{42}, None{}, None{}] : List<&2, Maybe<&2, U32>>}

law request_json_parses:
  {Http.Request.json(Http.Request.with_body(request("POST /e HTTP/1.1\r\nContent-Type: application/json; charset=utf-8\r"), "{\"a\":1}"))
    == Some{Json.Obj{[("a", Json.Num{"1"})]}} : Maybe<&2, Json.Value>}

law request_json_needs_content_type:
  {Http.Request.json(Http.Request.with_body(request("POST /e HTTP/1.1\r\nContent-Type: text/plain\r"), "{\"a\":1}"))
    == None{} : Maybe<&2, Json.Value>}

law response_of_json:
  {Http.Response.body(Http.Response.of_json(Json.Obj{[("ok", Json.Boolean{True{}})]})) == "{\"ok\":true}" : String}

# Forms
# -----

law split_seq_all_pieces:
  {Text.split_seq_all("a--b--c--", "--") == ["a", "b", "c", ""] : List<&2, String>}

law split_seq_all_no_hit:
  {Text.split_seq_all("abc", "--") == ["abc"] : List<&2, String>}

law query_all_repeats:
  {Http.Request.query_all(request("GET /t?tag=a&tag=b%20c&x=1 HTTP/1.1\r"), "tag") == ["a", "b c"] : List<&2, String>}

law query_all_absent:
  {Http.Request.query_all(request("GET /t?x=1 HTTP/1.1\r"), "tag") == [] : List<&2, String>}

law form_decodes:
  {Http.Request.form(Http.Request.with_body(request("POST /f HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r"), "a=1&b=x+y%21"), "b")
    == "x y!" : String}

law form_needs_media_type:
  {Http.Request.form(Http.Request.with_body(request("POST /f HTTP/1.1\r\nContent-Type: text/plain\r"), "a=1&b=x+y%21"), "b")
    == "" : String}

law form_all_repeats:
  {Http.Request.form_all(Http.Request.with_body(request("POST /f HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r"), "t=a&t=b&u=c"), "t")
    == ["a", "b"] : List<&2, String>}

law media_type_strips_params:
  {Http.Request.media_type(request("POST /f HTTP/1.1\r\nContent-Type: Multipart/Form-Data; boundary=xyz\r")) == "multipart/form-data" : String}

law boundary_quoted:
  {Form.boundary("multipart/form-data; boundary=\"ab c\"") == Some{"ab c"} : Maybe<&2, String>}

law boundary_wrong_type:
  {Form.boundary("application/json; boundary=x") == None{} : Maybe<&2, String>}

law multipart_two_parts:
  {Form.parse("multipart/form-data; boundary=XyZ", "--XyZ\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nhi\r\n--XyZ\r\nContent-Disposition: form-data; name=\"f\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\ndata\r\n--XyZ--\r\n")
    == Some{[Form.Part{"title", None{}, "text/plain", "hi"}, Form.Part{"f", Some{"a.txt"}, "text/plain", "data"}]}
    : Maybe<&2, List<&2, Form.Part>>}

law multipart_missing_blank:
  {Form.parse("multipart/form-data; boundary=XyZ", "--XyZ\r\nContent-Disposition: form-data; name=\"a\"\r\nx\r\n--XyZ--")
    == None{} : Maybe<&2, List<&2, Form.Part>>}

law multipart_unterminated:
  {Form.parse("multipart/form-data; boundary=XyZ", "--XyZ\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nx\r\n")
    == None{} : Maybe<&2, List<&2, Form.Part>>}

law multipart_wrong_type:
  {Form.parse("application/json", "--XyZ--") == None{} : Maybe<&2, List<&2, Form.Part>>}

law multipart_field_and_file:
  {[Form.field([Form.Part{"a", None{}, "text/plain", "x"}, Form.Part{"a", Some{"f.txt"}, "text/plain", "y"}], "a"),
    Form.Part.body(Maybe.default(&2, Form.Part, Form.file([Form.Part{"a", None{}, "text/plain", "x"}, Form.Part{"a", Some{"f.txt"}, "text/plain", "y"}], "a"), Form.Part{"", None{}, "", ""}))]
    == ["x", "y"] : List<&2, String>}

# Request headers
# ---------------

law cookie_parses:
  {Http.Request.cookie(request("GET / HTTP/1.1\r\nCookie: a=1; b=x=y\r"), "b") == "x=y" : String}

law cookie_missing:
  {Http.Request.cookie(request("GET / HTTP/1.1\r\nCookie: a=1\r"), "b") == "" : String}

law cookies_in_order:
  {Http.Request.cookies(request("GET / HTTP/1.1\r\nCookie: a=1; b=2\r")) == [("a", "1"), ("b", "2")] : List<&2, Text.Two()>}

law negotiate_thousandths:
  {[Negotiate.thousandths("1"), Negotiate.thousandths("0.8"), Negotiate.thousandths(".5"), Negotiate.thousandths("0.555"), Negotiate.thousandths("x")]
    == [1000, 800, 500, 555, 0] : List<&2, U32>}

law negotiate_q_order:
  {Negotiate.pick("text/html;q=0.8, application/json", ["text/html", "application/json"], False{}) == Some{"application/json"} : Maybe<&2, String>}

law negotiate_wildcard:
  {Negotiate.pick("*/*", ["text/plain"], False{}) == Some{"text/plain"} : Maybe<&2, String>}

law negotiate_specific_wins:
  {Negotiate.pick("text/*;q=1, text/plain;q=0.2", ["text/plain", "text/html"], False{}) == Some{"text/html"} : Maybe<&2, String>}

law negotiate_zero_excludes:
  {Negotiate.pick("gzip;q=0, identity", ["gzip", "identity"], False{}) == Some{"identity"} : Maybe<&2, String>}

law negotiate_absent_takes_first:
  {Negotiate.pick("", ["a", "b"], False{}) == Some{"a"} : Maybe<&2, String>}

law negotiate_nothing:
  {Negotiate.pick("image/png", ["text/plain"], False{}) == None{} : Maybe<&2, String>}

law negotiate_language_prefix:
  {Negotiate.pick("en, fr;q=0.5", ["fr-ca", "en-us"], True{}) == Some{"en-us"} : Maybe<&2, String>}

law negotiate_earliest_on_tie:
  {Negotiate.pick("a, b", ["b", "a"], False{}) == Some{"b"} : Maybe<&2, String>}

law client_ip_untrusted:
  {Http.Request.client_ip(request("GET / HTTP/1.1\r\nX-Forwarded-For: 1.1.1.1\r"), Http.NoProxy{}) == None{} : Maybe<&2, String>}

law client_ip_rightmost:
  {Http.Request.client_ip(request("GET / HTTP/1.1\r\nX-Forwarded-For: 1.1.1.1, 2.2.2.2\r"), Http.Proxy{}) == Some{"2.2.2.2"} : Maybe<&2, String>}

law client_ip_forwarded:
  {Http.Request.client_ip(request("GET / HTTP/1.1\r\nForwarded: for=1.1.1.1, for=\"[2001:db8::1]:8080\";proto=https\r"), Http.Proxy{}) == Some{"2001:db8::1"} : Maybe<&2, String>}

law client_ip_absent:
  {Http.Request.client_ip(request("GET / HTTP/1.1\r"), Http.Proxy{}) == None{} : Maybe<&2, String>}

law scheme_forwarded:
  {[Http.Request.scheme(request("GET / HTTP/1.1\r\nX-Forwarded-Proto: HTTPS\r"), Http.Proxy{}),
    Http.Request.scheme(request("GET / HTTP/1.1\r\nX-Forwarded-Proto: https\r"), Http.NoProxy{}),
    Http.Request.scheme(request("GET / HTTP/1.1\r\nForwarded: proto=https\r"), Http.Proxy{})]
    == ["https", "http", "https"] : List<&2, String>}

law host_header:
  {[Http.Request.host(request("GET / HTTP/1.1\r\nHost: example.com\r\nX-Forwarded-Host: app.example\r"), Http.NoProxy{}),
    Http.Request.host(request("GET / HTTP/1.1\r\nHost: example.com\r\nX-Forwarded-Host: app.example\r"), Http.Proxy{})]
    == ["example.com", "app.example"] : List<&2, String>}

law accepts_language_header:
  {Http.Request.accepts_language(request("GET / HTTP/1.1\r\nAccept-Language: pt-BR, en;q=0.5\r"), ["en-us", "pt-br"]) == Some{"pt-br"} : Maybe<&2, String>}

# Files
# -----

law fnv1a_known:
  {Text.fnv1a("a", Text.fnv_seed()) == 3826002220 : U32}

law hex_show_pads:
  {[Text.hex_show(255), Text.hex_show(3826002220)] == ["000000ff", "e40c292c"] : List<&2, String>}

law etag_shape:
  {Http.etag("hello") == "\"4f9f2cab-5\"" : String}

law etag_counts_bytes:
  {Http.etag("Olá") == "\"" ++ Text.hex_show(Text.fnv1a("Olá", Text.fnv_seed())) ++ "-4\"" : String}

law with_etag_headers:
  {[Http.Response.header(Http.Response.with_etag(Http.Response.text("hello")), "etag"),
    Http.Response.header(Http.Response.with_etag(Http.Response.text("hello")), "accept-ranges")]
    == ["\"4f9f2cab-5\"", "bytes"] : List<&2, String>}

law parse_range_forms:
  {[Http.Range.parse("bytes=0-9", 10), Http.Range.parse("bytes=5-", 10), Http.Range.parse("bytes=-3", 10), Http.Range.parse("", 10)]
    == [Http.Range{0, 9}, Http.Range{5, 9}, Http.Range{7, 9}, Http.NoRange{}] : List<&2, Http.Range>}

law parse_range_clamps:
  {[Http.Range.parse("bytes=0-99", 10), Http.Range.parse("bytes=-99", 10)] == [Http.Range{0, 9}, Http.Range{0, 9}] : List<&2, Http.Range>}

law parse_range_bad:
  {[Http.Range.parse("bytes=9-3", 10), Http.Range.parse("bytes=10-", 10), Http.Range.parse("chars=0-1", 10), Http.Range.parse("bytes=0-1,3-4", 10), Http.Range.parse("bytes=-0", 10), Http.Range.parse("bytes=x-1", 10)]
    == [Http.BadRange{}, Http.BadRange{}, Http.BadRange{}, Http.BadRange{}, Http.BadRange{}, Http.BadRange{}] : List<&2, Http.Range>}

law conditional_304:
  {Http.Response.render(Http.Response.conditional(request("GET / HTTP/1.1\r\nIf-None-Match: \"4f9f2cab-5\"\r"), Http.Response.with_etag(Http.Response.text("hello"))), False{}, True{})
    == "HTTP/1.1 304 Not Modified\r\naccept-ranges: bytes\r\nconnection: keep-alive\r\ncontent-type: text/plain; charset=utf-8\r\netag: \"4f9f2cab-5\"\r\ncontent-length: 5\r\n\r\n" : String}

law conditional_weak_and_list:
  {Http.Response.status(Http.Response.conditional(request("GET / HTTP/1.1\r\nIf-None-Match: \"other\", W/\"4f9f2cab-5\"\r"), Http.Response.with_etag(Http.Response.text("hello")))) == 304 : U32}

law conditional_star:
  {Http.Response.status(Http.Response.conditional(request("GET / HTTP/1.1\r\nIf-None-Match: *\r"), Http.Response.with_etag(Http.Response.text("hello")))) == 304 : U32}

law conditional_miss:
  {[Http.Response.status(Http.Response.conditional(request("GET / HTTP/1.1\r\nIf-None-Match: \"nope\"\r"), Http.Response.with_etag(Http.Response.text("hello")))),
    Http.Response.status(Http.Response.conditional(request("POST / HTTP/1.1\r\nIf-None-Match: \"4f9f2cab-5\"\r"), Http.Response.with_etag(Http.Response.text("hello")))),
    Http.Response.status(Http.Response.conditional(request("GET / HTTP/1.1\r"), Http.Response.with_etag(Http.Response.text("hello"))))]
    == [200, 200, 200] : List<&2, U32>}

law ranged_206:
  {[Http.Response.body(Http.Response.ranged(request("GET / HTTP/1.1\r\nRange: bytes=0-4\r"), Http.Response.text("hello world"))),
    Http.Response.header(Http.Response.ranged(request("GET / HTTP/1.1\r\nRange: bytes=0-4\r"), Http.Response.text("hello world")), "content-range"),
    U32.show(Http.Response.status(Http.Response.ranged(request("GET / HTTP/1.1\r\nRange: bytes=0-4\r"), Http.Response.text("hello world"))))]
    == ["hello", "bytes 0-4/11", "206"] : List<&2, String>}

law ranged_suffix:
  {Http.Response.body(Http.Response.ranged(request("GET / HTTP/1.1\r\nRange: bytes=-5\r"), Http.Response.text("hello world"))) == "world" : String}

law ranged_416:
  {[U32.show(Http.Response.status(Http.Response.ranged(request("GET / HTTP/1.1\r\nRange: bytes=20-\r"), Http.Response.text("hello world")))),
    Http.Response.header(Http.Response.ranged(request("GET / HTTP/1.1\r\nRange: bytes=20-\r"), Http.Response.text("hello world")), "content-range")]
    == ["416", "bytes */11"] : List<&2, String>}

law ranged_multibyte_416:
  {Http.Response.status(Http.Response.ranged(request("GET / HTTP/1.1\r\nRange: bytes=0-1\r"), Http.Response.text("héllo"))) == 416 : U32}

law ranged_passes_other_methods:
  {Http.Response.status(Http.Response.ranged(request("POST / HTTP/1.1\r\nRange: bytes=0-1\r"), Http.Response.text("hello"))) == 200 : U32}

# Streaming
# ---------

law chunk_frames:
  {[Http.chunk("Wiki"), Http.chunk("Olá"), Http.chunk("")] == ["4\r\nWiki\r\n", "4\r\nOlá\r\n", ""] : List<&2, String>}

law chunk_size_is_hex:
  {Http.chunk(String.repeat("x", 26n)) == "1a\r\n" ++ String.repeat("x", 26n) ++ "\r\n" : String}

law last_chunk_ends:
  {Http.last_chunk() == "0\r\n\r\n" : String}

law sse_event_format:
  {Http.Sse.event("tick", "a\nb") == "event: tick\ndata: a\ndata: b\n\n" : String}

law sse_data_format:
  {Http.Sse.data("x") == "data: x\n\n" : String}

# Responses
# ---------

law cookie_render_defaults:
  {Http.Cookie.render(Http.Cookie.new("sid", "abc")) == "sid=abc; Path=/; HttpOnly; SameSite=Lax" : String}

law cookie_render_full:
  {Http.Cookie.render(Http.Cookie.same_site(Http.Cookie.secure(Http.Cookie.with_max_age(Http.Cookie.with_domain(Http.Cookie.with_path(Http.Cookie.new("a", "1"), "/app"), "example.com"), 3600), True{}), "Strict"))
    == "a=1; Path=/app; Domain=example.com; Max-Age=3600; Secure; HttpOnly; SameSite=Strict" : String}

law cookie_same_site_none_forces_secure:
  {Http.Cookie.render(Http.Cookie.http_only(Http.Cookie.same_site(Http.Cookie.new("a", "1"), "None"), False{}))
    == "a=1; Path=/; Secure; SameSite=None" : String}

law cookie_session_has_no_age:
  {Http.Cookie.render(Http.Cookie.with_max_age(Http.Cookie.new("a", "1"), 0)) == "a=1; Path=/; HttpOnly; SameSite=Lax" : String}

law expire_cookie_line:
  {Http.Response.render(Http.Response.expire_cookie(Http.Response.empty(204), "sid"), False{}, False{})
    == "HTTP/1.1 204 No Content\r\nconnection: close\r\nset-cookie: sid=; Path=/; Max-Age=0\r\n\r\n" : String}

law render_two_cookies_in_order:
  {Http.Response.render(Http.Response.with_cookie(Http.Response.with_cookie(Http.Response.text("x"), Http.Cookie.new("a", "1")), Http.Cookie.new("b", "2")), False{}, True{})
    == "HTTP/1.1 200 OK\r\nconnection: keep-alive\r\ncontent-type: text/plain; charset=utf-8\r\nset-cookie: a=1; Path=/; HttpOnly; SameSite=Lax\r\nset-cookie: b=2; Path=/; HttpOnly; SameSite=Lax\r\ncontent-length: 1\r\n\r\nx" : String}

law with_type_adds_charset:
  {Http.Response.header(Http.Response.with_type(Http.Response.empty(200), "text/css"), "content-type") == "text/css; charset=utf-8" : String}

law with_type_keeps_binary:
  {Http.Response.header(Http.Response.with_type(Http.Response.empty(200), "image/png"), "content-type") == "image/png" : String}

law with_type_keeps_params:
  {Http.Response.header(Http.Response.with_type(Http.Response.empty(200), "text/plain; charset=latin1"), "content-type") == "text/plain; charset=latin1" : String}

law send_infers_html:
  {Http.Response.header(Http.Response.send("  <h1>x</h1>"), "content-type") == "text/html; charset=utf-8" : String}

law send_infers_json:
  {Http.Response.header(Http.Response.send("[1]"), "content-type") == "application/json; charset=utf-8" : String}

law send_infers_text:
  {Http.Response.header(Http.Response.send("hello"), "content-type") == "text/plain; charset=utf-8" : String}

law see_other_status:
  {[Http.Response.status(Http.Response.see_other("/x")), Http.Response.status(Http.Response.moved("/x")), Http.Response.status(Http.Response.temporary_redirect("/x")), Http.Response.status(Http.Response.permanent_redirect("/x")), Http.Response.status(Http.Response.redirect("/x"))]
    == [303, 301, 307, 308, 302] : List<&2, U32>}

law see_other_location:
  {Http.Response.header(Http.Response.see_other("/x"), "location") == "/x" : String}

law reasons_added:
  {[Http.Status.reason(206), Http.Status.reason(303), Http.Status.reason(307), Http.Status.reason(416)]
    == ["Partial Content", "See Other", "Temporary Redirect", "Range Not Satisfiable"] : List<&2, String>}

# Timeouts
# --------

law arm_from_now:
  {Race.Arm.at(1000n, 250) == 1250n : Nat}

law arm_none_is_never:
  {Race.Arm.at(1000n, 0) == 0n : Nat}

law arm_next_bumps_gen:
  {Race.Arm.next(Race.Arm{3, 0n}, 1000n, 250) == Race.Arm{4, 1250n} : Race.Arm}

law arm_due_after:
  {Race.Arm.due(Race.Arm{1, 1250n}, 1250n) == True{} : Bool}

law arm_not_due_before:
  {Race.Arm.due(Race.Arm{1, 1250n}, 1249n) == False{} : Bool}

law arm_disarmed_never_due:
  {Race.Arm.due(Race.Arm{1, 0n}, 99999n) == False{} : Bool}

law arm_sleep_to_deadline:
  {Race.Arm.sleep(Race.Arm{1, 1250n}, 1000n, 10000) == 250 : U32}

law arm_sleep_capped:
  {Race.Arm.sleep(Race.Arm{1, 90000n}, 1000n, 10000) == 10000 : U32}

law arm_sleep_disarmed:
  {Race.Arm.sleep(Race.Arm{1, 0n}, 1000n, 10000) == 10000 : U32}

law arm_sleep_at_least_1:
  {Race.Arm.sleep(Race.Arm{1, 1000n}, 1000n, 10000) == 1 : U32}

law step_is_shortest:
  {Server.Timeouts.step(Server.Timeouts{15000, 10000, 30000, 30000, 30000, 10000}) == 10000 : U32}

law step_skips_zero:
  {Server.Timeouts.step(Server.Timeouts{0, 0, 30000, 0, 20000, 10000}) == 20000 : U32}

law step_all_zero:
  {Server.Timeouts.step(Server.Timeouts{0, 0, 0, 0, 0, 10000}) == 0 : U32}

# Draining
# --------

law tally_admits_open:
  {Drain.Tally.admit(Drain.Open{2}) == True{} : Bool}

law tally_refuses_draining:
  {Drain.Tally.admit(Drain.Draining{2}) == False{} : Bool}

law tally_enter_counts:
  {Drain.Tally.enter(Drain.Open{2}) == Drain.Open{3} : Drain.Tally}

law tally_enter_draining_stays:
  {Drain.Tally.enter(Drain.Draining{2}) == Drain.Draining{2} : Drain.Tally}

law tally_leave_counts:
  {Drain.Tally.leave(Drain.Draining{2}) == Drain.Draining{1} : Drain.Tally}

law tally_drain_keeps_count:
  {Drain.Tally.drain(Drain.Open{2}) == Drain.Draining{2} : Drain.Tally}

law tally_clear_when_drained:
  {Drain.Tally.clear(Drain.Draining{0}) == True{} : Bool}

law tally_not_clear_in_flight:
  {Drain.Tally.clear(Drain.Draining{1}) == False{} : Bool}

law tally_not_clear_open:
  {Drain.Tally.clear(Drain.Open{0}) == False{} : Bool}

# Middleware
# ----------

# A middleware that changes nothing, for laws about wrapped route lists.
def ident(next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  next(req)

law local_round_trip:
  {Http.Request.local(Http.Request.with_local(request("GET / HTTP/1.1\r"), "user", "v"), "user") == "v" : String}

law local_absent:
  {Http.Request.local(request("GET / HTTP/1.1\r"), "user") == "" : String}

law local_keeps_params:
  {Http.Request.param(
    Http.Request.with_local(
      Http.Request.with_params(request("GET / HTTP/1.1\r"), Map.set(&2, String, Map.new(&2, String), "id", "1")),
      "k", "v"),
    "id") == "1" : String}

law wrap_keeps_patterns:
  {Router.pattern_of(Router.wrap(~ident, [Router.get("/a/:id", noop), Router.post("/b", noop)]))
    == Router.pattern_of([Router.get("/a/:id", noop), Router.post("/b", noop)])
    : List<&2, List<&2, Router.Seg>>}

law wrap_keeps_conflicts:
  {Router.conflicts(Router.wrap(~ident, [Router.get("/a", noop), Router.get("/a", noop)]))
    == ["duplicate route: GET /a"]
    : List<&2, String>}

# Errors
# ------

law error_status_not_found:
  {Http.Error.status(Http.NotFound{""}) == 404 : U32}

law error_status_other:
  {Http.Error.status(Http.Status{418, ""}) == 418 : U32}

law error_reason_gone:
  {Http.Status.reason(Http.Error.status(Http.Gone{""})) == "Gone" : String}

law fail_carries_status:
  {Http.Response.status(Http.Response.fail(Http.Forbidden{"x"})) == 403 : U32}

law fail_reads_back:
  {Http.Response.error(Http.Response.fail(Http.Conflict{"c"})) == Some{Http.Conflict{"c"}} : Maybe<&2, Http.Error>}

law whole_has_no_error:
  {Http.Response.error(Http.Response.text("hi")) == None{} : Maybe<&2, Http.Error>}

law settle_prod_hides_detail:
  {Http.Response.body(Http.Response.settle(Http.Prod{}, Http.Response.fail(Http.Internal{"disk"})))
    == "Internal Server Error" : String}

law settle_dev_shows_detail:
  {Http.Response.body(Http.Response.settle(Http.Dev{}, Http.Response.fail(Http.Internal{"disk"})))
    == "Internal Server Error\ndisk" : String}

law settle_keeps_type:
  {Http.Response.header(Http.Response.settle(Http.Prod{}, Http.Response.with_type(Http.Response.fail(Http.NotFound{""}), "text/html")), "content-type")
    == "text/html; charset=utf-8" : String}

law not_found_is_failed:
  {Http.Response.error(Http.Response.not_found()) == Some{Http.NotFound{""}} : Maybe<&2, Http.Error>}

# The wire form of the router's 404 is what it was before errors became
# values, and it never carries a detail.
law not_found_renders_same:
  {Http.Response.render(Http.Response.not_found(), False{}, True{})
    == "HTTP/1.1 404 Not Found\r\nconnection: keep-alive\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 9\r\n\r\nNot Found"
    : String}

law json_prod_shape:
  {Http.Response.body(Errors.json(Http.Prod{}, request("GET /nope HTTP/1.1\r"), Http.NotFound{"d"}))
    == "{\"status\":404,\"error\":\"Not Found\"}" : String}

law json_dev_shape:
  {Http.Response.body(Errors.json(Http.Dev{}, request("GET /nope HTTP/1.1\r"), Http.NotFound{"d"}))
    == "{\"status\":404,\"error\":\"Not Found\",\"detail\":\"d\",\"path\":\"/nope\"}" : String}

law plain_dev_shape:
  {Http.Response.body(Errors.plain(Http.Dev{}, request("GET /nope HTTP/1.1\r"), Http.NotFound{"d"}))
    == "Not Found\nGET /nope\nd" : String}

# A rendered error keeps what the failed response carried.
law inherit_keeps_allow:
  {Http.Response.header(Http.Response.inherit(Http.Response.method_not_allowed("GET"), Http.Response.text("x")), "allow")
    == "GET" : String}

law inherit_renderer_wins:
  {Http.Response.header(
    Http.Response.inherit(
      Http.Response.with_header(Http.Response.fail(Http.NotFound{""}), "content-type", "a"),
      Http.Response.text("x")),
    "content-type") == "text/plain; charset=utf-8" : String}

law inherit_keeps_cookies:
  {Http.Response.cookies(
    Http.Response.inherit(
      Http.Response.with_cookie(Http.Response.fail(Http.NotFound{""}), Http.Cookie.new("a", "1")),
      Http.Response.text("x")))
    == [Http.Cookie.render(Http.Cookie.new("a", "1"))] : List<&2, String>}

law default_header_sets_absent:
  {Http.Response.header(Http.Response.with_default_header(Http.Response.text(""), "x-a", "1"), "x-a") == "1" : String}

law default_header_keeps_present:
  {Http.Response.header(Http.Response.with_default_header(Http.Response.with_header(Http.Response.text(""), "x-a", "0"), "x-a", "1"), "x-a") == "0" : String}

# CORS
# ----

law cors_any_allows:
  {Cors.allowed(Cors.any(), "http://a.test") == True{} : Bool}

law cors_list_exact:
  {Cors.allowed(Cors.new(["http://a.test"]), "http://a.test:81") == False{} : Bool}

law cors_list_hit:
  {Cors.allowed(Cors.new(["http://b.test", "http://a.test"]), "http://a.test") == True{} : Bool}

law cors_star_without_creds:
  {Cors.origin_value(Cors.any(), "http://a.test") == "*" : String}

law cors_echo_with_creds:
  {Cors.origin_value(Cors.with_credentials(Cors.any(), True{}), "http://a.test") == "http://a.test" : String}

law cors_echo_with_list:
  {Cors.origin_value(Cors.new(["http://a.test"]), "http://a.test") == "http://a.test" : String}

law cors_vary_appends:
  {Http.Response.header(Cors.add_vary(Http.Response.with_header(Http.Response.text(""), "vary", "Accept")), "vary")
    == "Accept, origin" : String}

law cors_vary_once:
  {Http.Response.header(Cors.add_vary(Http.Response.with_header(Http.Response.text(""), "vary", "Origin")), "vary")
    == "Origin" : String}

law cors_preflight_echoes_headers:
  {Http.Response.header(
    Cors.preflight(Cors.any(), "http://a.test",
      request("OPTIONS /x HTTP/1.1\r\nOrigin: http://a.test\r\nAccess-Control-Request-Method: POST\r\nAccess-Control-Request-Headers: x-a\r")),
    "access-control-allow-headers") == "x-a" : String}

law cors_preflight_status:
  {Http.Response.status(Cors.preflight(Cors.any(), "http://a.test", request("OPTIONS /x HTTP/1.1\r\nAccess-Control-Request-Method: POST\r")))
    == 204 : U32}

law cors_is_preflight:
  {Cors.is_preflight(request("OPTIONS /x HTTP/1.1\r\nAccess-Control-Request-Method: POST\r")) == True{} : Bool}

law cors_plain_options_not_preflight:
  {Cors.is_preflight(request("OPTIONS /x HTTP/1.1\r")) == False{} : Bool}

# Shield
# ------

law shield_default_nosniff:
  {Http.Response.header(Shield.apply(Shield.default(), Http.Response.text("")), "x-content-type-options") == "nosniff" : String}

law shield_handler_wins:
  {Http.Response.header(Shield.apply(Shield.default(), Http.Response.with_header(Http.Response.text(""), "x-frame-options", "SAMEORIGIN")), "x-frame-options")
    == "SAMEORIGIN" : String}

law shield_hsts_opt_in:
  {Http.Response.header(Shield.apply(Shield.default(), Http.Response.text("")), "strict-transport-security") == "" : String}

law shield_with_hsts:
  {Http.Response.header(Shield.apply(Shield.with_hsts(Shield.default(), 3600), Http.Response.text("")), "strict-transport-security")
    == "max-age=3600; includeSubDomains" : String}

law shield_with_header_replaces:
  {Http.Response.header(Shield.apply(Shield.with_frame(Shield.default(), "SAMEORIGIN"), Http.Response.text("")), "x-frame-options")
    == "SAMEORIGIN" : String}

# Static files
# ------------

law static_safe_plain:
  {Static.safe(["css", "app.css"]) == True{} : Bool}

law static_refuses_dotdot:
  {Static.safe(["..", "main.bend"]) == False{} : Bool}

law static_refuses_dot:
  {Static.safe(["a", "."]) == False{} : Bool}

law static_refuses_slash:
  {Static.safe(["a/b"]) == False{} : Bool}

law static_refuses_backslash:
  {Static.safe(["a\\b"]) == False{} : Bool}

law static_hides_dotfiles:
  {Static.safe([".env"]) == False{} : Bool}

law static_refuses_empty:
  {Static.safe([""]) == False{} : Bool}

law static_mime_html:
  {Static.mime_of("index.html") == "text/html" : String}

law static_mime_upper:
  {Static.mime_of("APP.JS") == "text/javascript" : String}

law static_mime_last_dot:
  {Static.mime_of("dir.v2/archive.tar.gz") == "application/octet-stream" : String}

law static_mime_dotted_dir:
  {Static.mime_of("dir.v2/README") == "application/octet-stream" : String}

law static_index_root:
  {Static.target("/", "") == "index.html" : String}

law static_index_dir:
  {Static.target("/docs/", "docs") == "docs/index.html" : String}

law static_file:
  {Static.target("/docs/a.css", "docs/a.css") == "docs/a.css" : String}

# Request ids and logging
# -----------------------

law log_safe_id_plain:
  {Random.safe_id("abc-123.X_y") == True{} : Bool}

law log_safe_id_empty:
  {Random.safe_id("") == False{} : Bool}

law log_safe_id_space:
  {Random.safe_id("a b") == False{} : Bool}

law log_safe_id_long:
  {Random.safe_id(String.repeat("a", 129n)) == False{} : Bool}

law log_safe_id_max:
  {Random.safe_id(String.repeat("a", 128n)) == True{} : Bool}

law log_hex_id_len:
  {Text.byte_length(Random.hex_id(0, 1), 0) == 16 : U32}

law log_hex_id_padded:
  {Random.hex_id(255, 4096) == "000000ff00001000" : String}

law log_line_escapes:
  {Log.line("5", "i", "", "GET", "/a\"b", 200, 2n)
    == "{\"ts\":5,\"id\":\"i\",\"method\":\"GET\",\"path\":\"/a\\\"b\",\"status\":200,\"ms\":2}" : String}

# With tracing on, the trace id follows the request id.
law log_line_trace:
  {Log.line("1790000000000", "i", "4bf92f3577b34da6a3ce929d0e0e4736", "GET", "/", 200, 0n)
    == "{\"ts\":1790000000000,\"id\":\"i\",\"trace_id\":\"4bf92f3577b34da6a3ce929d0e0e4736\",\"method\":\"GET\",\"path\":\"/\",\"status\":200,\"ms\":0}" : String}

# Store and rate limiting
# -----------------------

law store_ns_default_empty:
  {Store.ns_of(Map.new(&2, Map<&2, String>), "x") == Map.new(&2, String) : Map<&2, String>}

law request_store_seeded_none:
  {Http.Request.store(request("GET / HTTP/1.1\r")) == None{} : Maybe<&2, Chan(Map<&2, Map<&2, String>>)>}

law rate_epoch:
  {Rate.epoch(125000n, 60000) == 2 : U32}

# A map of window 2 with nine hits on `k`.
def window_two() -> Map<&2, String>:
  Map.set(&2, String, Map.set(&2, String, Map.new(&2, String), "_epoch", "2"), "k", "9")

law rate_tick_same_window:
  {Rate.count("k", Rate.tick(2, "k", window_two())) == 10 : U32}

law rate_tick_new_window:
  {Rate.count("k", Rate.tick(3, "k", window_two())) == 1 : U32}

law rate_tick_other_key:
  {Rate.count("j", Rate.tick(2, "j", window_two())) == 1 : U32}

law rate_reset_in_min_one:
  {Rate.reset_in(119999n, 60000) == 1 : U32}

law rate_reset_in_full:
  {Rate.reset_in(120000n, 60000) == 60 : U32}

law rate_refuse_status:
  {Http.Response.status(Rate.refuse(5, 60000, 6, 30)) == 429 : U32}

law rate_refuse_retry_after:
  {Http.Response.header(Rate.refuse(5, 60000, 6, 30), "retry-after") == "30" : String}

law rate_refuse_is_failed:
  {Http.Response.error(Rate.refuse(5, 60000, 6, 30)) == Some{Http.TooMany{"rate limit: 6 of 5 per 60000 ms"}} : Maybe<&2, Http.Error>}

law rate_remaining_floor:
  {Http.Response.header(Rate.decorate(5, 9, 1, Http.Response.text("")), "x-ratelimit-remaining") == "0" : String}

law rate_remaining_counts:
  {Http.Response.header(Rate.decorate(5, 2, 1, Http.Response.text("")), "x-ratelimit-remaining") == "3" : String}

# Sessions
# --------

law session_alive_fresh:
  {Session.alive(1000, 500, Session.touch(800, Map.new(&2, String))) == True{} : Bool}

law session_dead_old:
  {Session.alive(2000, 500, Session.touch(800, Map.new(&2, String))) == False{} : Bool}

law session_dead_unseen:
  {Session.alive(2000, 500, Map.new(&2, String)) == False{} : Bool}

law session_dead_future:
  {Session.alive(500, 500, Session.touch(800, Map.new(&2, String))) == False{} : Bool}

law session_encode_decode:
  {Session.decode(Session.encode(Map.set(&2, String, Session.touch(5, Map.new(&2, String)), "n", "a\"b")))
    == Map.set(&2, String, Session.touch(5, Map.new(&2, String)), "n", "a\"b") : Map<&2, String>}

law session_decode_garbage:
  {Session.decode("nope") == Map.new(&2, String) : Map<&2, String>}

# Two sessions, one dead and one live.
def sessions_mixed() -> Map<&2, String>:
  Map.set(&2, String,
    Map.set(&2, String, Map.new(&2, String), "old", Session.encode(Session.touch(100, Map.new(&2, String)))),
    "new", Session.encode(Session.touch(1900, Map.new(&2, String))))

law session_sweep_keeps_live:
  {Map.keys(&2, String, Session.sweep(2000, 500, sessions_mixed())) == ["new"] : List<&2, String>}

law session_cookie_defaults:
  {Http.Cookie.render(Session.cookie(Session.default(), "id")) == "air_session=id; Path=/; HttpOnly; SameSite=Lax" : String}

law session_cookie_secure:
  {Http.Cookie.render(Session.cookie(Session.secure(Session.default(), True{}), "id"))
    == "air_session=id; Path=/; Secure; HttpOnly; SameSite=Lax" : String}

# Schema validation
# -----------------

law schema_str_ok:
  {Schema.errors(Schema.str(), Json.of_str("a")) == [] : List<&2, String>}

law schema_str_wrong:
  {Schema.errors(Schema.str(), Json.of_u32(1)) == ["expected string"] : List<&2, String>}

law schema_obj_missing:
  {Schema.errors(Schema.obj([Schema.field("a", Schema.str())]), Json.obj([])) == ["missing: a"] : List<&2, String>}

law schema_obj_optional:
  {Schema.errors(Schema.obj([Schema.optional("a", Schema.str())]), Json.obj([])) == [] : List<&2, String>}

law schema_obj_unknown:
  {Schema.errors(Schema.obj([]), Json.obj([Json.field("x", Json.null())])) == ["unknown: x"] : List<&2, String>}

law schema_obj_open:
  {Schema.errors(Schema.obj_open([]), Json.obj([Json.field("x", Json.null())])) == [] : List<&2, String>}

law schema_order:
  {Schema.errors(
    Schema.obj([Schema.field("title", Schema.str()), Schema.field("done", Schema.boolean())]),
    Json.obj([Json.field("title", Json.of_u32(5))]))
    == ["title: expected string", "missing: done"] : List<&2, String>}

law schema_arr_index:
  {Schema.errors(Schema.arr(Schema.int()), Json.arr([Json.of_u32(1), Json.of_str("b")])) == ["[1]: expected integer"] : List<&2, String>}

law schema_enum:
  {Schema.errors(Schema.one_of(["a", "b"]), Json.of_str("c")) == ["expected one of a, b"] : List<&2, String>}

law schema_nested_path:
  {Schema.errors(
    Schema.obj([Schema.field("u", Schema.obj([Schema.field("n", Schema.str())]))]),
    Json.obj([Json.field("u", Json.obj([Json.field("n", Json.null())]))]))
    == ["u.n: expected string"] : List<&2, String>}

law schema_strict_int:
  {Schema.errors(Schema.int(), Json.of_str("42")) == ["expected integer"] : List<&2, String>}

law schema_lenient_int:
  {Schema.check_strings(Schema.obj_open([Schema.field("limit", Schema.int())]), Map.set(&2, String, Map.new(&2, String), "limit", "42"))
    == [] : List<&2, String>}

law schema_lenient_bad_int:
  {Schema.check_strings(Schema.obj_open([Schema.field("limit", Schema.int())]), Map.set(&2, String, Map.new(&2, String), "limit", "x"))
    == ["limit: expected integer"] : List<&2, String>}

law schema_422_body:
  {Http.Response.body(Schema.unprocessable(["a: expected string"]))
    == "{\"status\":422,\"error\":\"Unprocessable Content\",\"errors\":[\"a: expected string\"]}" : String}

# Templates
# ---------

law view_lex_text_var:
  {View.lex("a {{b}} c") == [View.TText{"a "}, View.TVar{"b"}, View.TText{" c"}] : List<&2, View.Tok>}

law view_lex_raw:
  {View.lex("{{{b}}}") == [View.TRaw{"b"}] : List<&2, View.Tok>}

law view_lex_section:
  {View.lex("{{# x }}y{{/x}}") == [View.TOpen{"x"}, View.TText{"y"}, View.TClose{"x"}] : List<&2, View.Tok>}

law view_lex_unterminated:
  {View.lex("a {{b") == [View.TText{"a "}, View.TText{"{{b"}] : List<&2, View.Tok>}

def one(k: String, v: Json.Value) -> Json.Value:
  Json.obj([Json.field(k, v)])

law view_escapes:
  {View.render("<b>{{x}}</b>", one("x", Json.of_str("<&>\"'"))) == "<b>&lt;&amp;&gt;&quot;&#39;</b>" : String}

law view_raw:
  {View.render("{{{x}}}", one("x", Json.of_str("<i>"))) == "<i>" : String}

law view_missing_empty:
  {View.render("[{{x}}]", Json.obj([])) == "[]" : String}

law view_list:
  {View.render("{{#xs}}<{{.}}>{{/xs}}", one("xs", Json.arr([Json.of_u32(1), Json.of_u32(2)]))) == "<1><2>" : String}

law view_inverted:
  {View.render("{{^xs}}none{{/xs}}", one("xs", Json.arr([]))) == "none" : String}

law view_truthy_object:
  {View.render("{{#u}}{{name}}{{/u}}", one("u", one("name", Json.of_str("n")))) == "n" : String}

law view_stack_lookup:
  {View.render("{{#xs}}{{.}}{{sep}}{{/xs}}",
    Json.obj([Json.field("sep", Json.of_str(",")), Json.field("xs", Json.arr([Json.of_str("a"), Json.of_str("b")]))]))
    == "a,b," : String}

law view_dotted:
  {View.render("{{u.name}}", one("u", one("name", Json.of_str("n")))) == "n" : String}

law view_nested_sections:
  {View.render("{{#a}}{{#b}}x{{/b}}{{/a}}", Json.obj([Json.field("a", Json.of_bool(True{})), Json.field("b", Json.of_bool(True{}))])) == "x" : String}

law view_unclosed_section:
  {View.render("{{#a}}x", one("a", Json.of_bool(True{}))) == "x" : String}

law view_false_skips:
  {View.render("[{{#a}}x{{/a}}]", one("a", Json.of_bool(False{}))) == "[]" : String}

# Testing
# -------

law test_get_raw:
  {Test.get("/a?b=1") == "GET /a?b=1 HTTP/1.1\r\nhost: test\r\n\r\n" : String}

# The length is in bytes: "é" is two.
law test_post_length:
  {Test.post("/e", "text/plain", "héllo")
    == "POST /e HTTP/1.1\r\nhost: test\r\ncontent-type: text/plain\r\ncontent-length: 6\r\n\r\nhéllo" : String}

law test_with_header:
  {Test.with_header("x-a", "1", Test.get("/"))
    == "GET / HTTP/1.1\r\nhost: test\r\nx-a: 1\r\n\r\n" : String}

# The refusal the server sends is the one tests get, byte for byte.
law refusal_render:
  {Http.Response.render(Http.Response.refusal(431), False{}, False{})
    == "HTTP/1.1 431 Request Header Fields Too Large\r\nconnection: close\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 31\r\n\r\nRequest Header Fields Too Large" : String}

# What `refuse` built inline before `refusal` existed.
law refusal_unchanged:
  {Http.Response.refusal(503) == Http.Response.with_status(Http.Response.text(Http.Status.reason(503)), 503) : Http.Response}

law test_takes_body_by_length:
  {Test.Prepared.body(Test.prepare(Http.Limits.default(), "POST / HTTP/1.1\r\ncontent-length: 3\r\n\r\nabcdef"))
    == "abc" : String}

law test_refuses_long_head:
  {Test.Prepared.refused(Test.prepare(Http.Limits{16, 100, 8192, 1048576}, "GET /a-long-path HTTP/1.1\r\n\r\n"))
    == 431 : U32}

law test_refuses_long_body:
  {Test.Prepared.refused(Test.prepare(Http.Limits{16384, 100, 8192, 2}, "POST / HTTP/1.1\r\ncontent-length: 3\r\n\r\nabc"))
    == 413 : U32}

law test_refuses_short_body:
  {Test.Prepared.refused(Test.prepare(Http.Limits.default(), "POST / HTTP/1.1\r\ncontent-length: 9\r\n\r\nabc"))
    == 400 : U32}

law test_refuses_unended_head:
  {Test.Prepared.refused(Test.prepare(Http.Limits.default(), "GET / HTTP/1.1\r\n")) == 400 : U32}

law test_refuses_parse:
  {Test.Prepared.refused(Test.prepare(Http.Limits.default(), "GET / HTTP/2.0\r\n\r\n")) == 505 : U32}

# Config
# ------

def env_sample() -> String:
  "A=1\n# a comment\n\nexport B = \"two words\"\nC='x=y'\nnope\n=x\nA=2\n"

# Comments and blanks skipped, `export` dropped, quotes off, the first
# `=` splits, a later line wins.
law config_parse:
  {[Text.map_get(Config.parse(env_sample()), "A", ""),
    Text.map_get(Config.parse(env_sample()), "B", ""),
    Text.map_get(Config.parse(env_sample()), "C", "")]
    == ["2", "two words", "x=y"] : List<&2, String>}

law config_parse_keys:
  {Map.keys(&2, String, Config.parse(env_sample())) == ["A", "B", "C"] : List<&2, String>}

law config_malformed:
  {Config.malformed(env_sample()) == [6, 7] : List<&2, U32>}

law config_hidden:
  {Config.show_value("DB_password", "hunter2") == "<hidden>" : String}

law config_shown:
  {Config.show_value("PORT", "80x") == "\"80x\"" : String}

law config_limits_default:
  {Config.limits_of("", "", "", "") == Http.Limits.default() : Http.Limits}

law config_limits_body:
  {Config.limits_of("", "", "", "10") == Http.Limits{16384, 100, 8192, 10} : Http.Limits}

law config_limits_bad:
  {Config.limits_problems("", "", "", "1e3") == ["AIR_MAX_BODY is not a number: \"1e3\""] : List<&2, String>}

law config_timeouts_default:
  {Config.timeouts_of("", "", "", "", "", "") == Server.Timeouts.default() : Server.Timeouts}

law config_port_range:
  {Config.port_problems("70000") == ["PORT is out of range: \"70000\""] : List<&2, String>}

law config_port_ok:
  {Config.port_problems("9090") == [] : List<&2, String>}

# Hooks
# -----

def tag(req: Http.Request, res: Http.Response) -> IO(Http.Response):
  IO.pure(Http.Response, Http.Response.with_header(res, "x-tag", "1"))

law hooks_on_send_pure:
  {Hooks.on_send(tag, noop, request("GET / HTTP/1.1\r"))
    == IO.pure(Http.Response, Http.Response.with_header(Http.Response.empty(204), "x-tag", "1")) : IO(Http.Response)}

def with_a(req: Http.Request) -> IO(Http.Request):
  IO.pure(Http.Request, Http.Request.with_local(req, "a", "1"))

def show_a(req: Http.Request) -> IO(Http.Response):
  IO.pure(Http.Response, Http.Response.text(Http.Request.local(req, "a")))

# The chain gets the request `on_request`'s function answers.
law hooks_on_request_feeds:
  {Hooks.on_request(with_a, show_a, request("GET / HTTP/1.1\r"))
    == IO.pure(Http.Response, Http.Response.text("1")) : IO(Http.Response)}

def missing(req: Http.Request) -> IO(Http.Response):
  IO.pure(Http.Response, Http.Response.fail(Http.NotFound{"x"}))

def ignore(req: Http.Request, e: Http.Error) -> IO(Unit):
  IO.pure(Unit, Unit{})

# `on_fail` observes: the failure goes on unchanged, for `on_error`.
law hooks_on_fail_unchanged:
  {Hooks.on_fail(ignore, missing, request("GET / HTTP/1.1\r"))
    == IO.pure(Http.Response, Http.Response.fail(Http.NotFound{"x"})) : IO(Http.Response)}

# Health
# ------

def checks(a: String, b: String) -> Map<&2, String>:
  Map.set(&2, String, Map.set(&2, String, Map.new(&2, String), "db", b), "cache", a)

law ready_ok:
  {Http.Response.status(Health.readiness("", Map.new(&2, String))) == 200 : U32}

law ready_body:
  {Http.Response.body(Health.readiness("", checks("1", "1"))) == "{\"status\":\"ready\"}" : String}

law ready_draining:
  {Http.Response.body(Health.readiness("1", checks("1", "1"))) == "{\"status\":\"draining\"}" : String}

law ready_down:
  {Http.Response.body(Health.readiness("", checks("0", "1")))
    == "{\"status\":\"not ready\",\"down\":[\"cache\"]}" : String}

law ready_down_503:
  {Http.Response.status(Health.readiness("", checks("0", "0"))) == 503 : U32}

law ready_down_sorted:
  {Health.down_checks(checks("0", "0")) == ["cache", "db"] : List<&2, String>}

law ready_no_store:
  {Http.Response.header(Health.readiness("1", Map.new(&2, String)), "cache-control") == "no-store" : String}

law health_ok:
  {Http.Response.body(Health.liveness()) == "{\"status\":\"ok\"}" : String}

# OpenAPI
# -------

law oa_str:
  {Json.render(OpenApi.to_json_schema(Schema.str())) == "{\"type\":\"string\"}" : String}

law oa_obj_strict:
  {Json.render(OpenApi.to_json_schema(Schema.obj([Schema.field("a", Schema.int()), Schema.optional("b", Schema.str())])))
    == "{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":4294967295},\"b\":{\"type\":\"string\"}},\"required\":[\"a\"],\"additionalProperties\":false}" : String}

law oa_obj_open:
  {Json.render(OpenApi.to_json_schema(Schema.obj_open([Schema.optional("q", Schema.any())])))
    == "{\"type\":\"object\",\"properties\":{\"q\":{}}}" : String}

law oa_arr_enum:
  {Json.render(OpenApi.to_json_schema(Schema.arr(Schema.one_of(["x"]))))
    == "{\"type\":\"array\",\"items\":{\"type\":\"string\",\"enum\":[\"x\"]}}" : String}

law oa_nested:
  {Json.render(OpenApi.to_json_schema(Schema.obj([Schema.field("u", Schema.obj([Schema.field("n", Schema.null())]))])))
    == "{\"type\":\"object\",\"properties\":{\"u\":{\"type\":\"object\",\"properties\":{\"n\":{\"type\":\"null\"}},\"required\":[\"n\"],\"additionalProperties\":false}},\"required\":[\"u\"],\"additionalProperties\":false}" : String}

law oa_template:
  {OpenApi.template(Router.parse_pattern("/users/:id/files/*rest")) == "/users/{id}/files/{rest}" : String}

law oa_template_root:
  {OpenApi.template(Router.parse_pattern("/")) == "/" : String}

law oa_operation_id:
  {OpenApi.operation_id("get", "/api/hello/{name}") == "get_api_hello_name" : String}

law oa_mount_keeps_notes:
  {Json.render(OpenApi.document("t", "1", Router.mount("/api", [OpenApi.summary("s", Router.get("/x", noop))])))
    == "{\"openapi\":\"3.1.0\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"servers\":[{\"url\":\"/\"}],\"paths\":{\"/api/x\":{\"get\":{\"operationId\":\"get_api_x\",\"summary\":\"s\",\"responses\":{\"default\":{\"description\":\"response\"}}}}}}" : String}

# Two methods on one path share its path item, in route order; a path
# param is listed; a body brings its 400 and 422.
law oa_document:
  {Json.render(OpenApi.document("t", "1", [
      OpenApi.returns(200, Schema.str(), Router.get("/t/:id", noop)),
      OpenApi.body(Schema.boolean(), Router.post("/t/:id", noop))
    ]))
    == "{\"openapi\":\"3.1.0\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"servers\":[{\"url\":\"/\"}],\"paths\":{\"/t/{id}\":{\"get\":{\"operationId\":\"get_t_id\",\"parameters\":[{\"name\":\"id\",\"in\":\"path\",\"required\":true,\"schema\":{\"type\":\"string\"}}],\"responses\":{\"200\":{\"description\":\"OK\",\"content\":{\"application/json\":{\"schema\":{\"type\":\"string\"}}}}}},\"post\":{\"operationId\":\"post_t_id\",\"parameters\":[{\"name\":\"id\",\"in\":\"path\",\"required\":true,\"schema\":{\"type\":\"string\"}}],\"requestBody\":{\"required\":true,\"content\":{\"application/json\":{\"schema\":{\"type\":\"boolean\"}}}},\"responses\":{\"400\":{\"description\":\"Bad Request\"},\"422\":{\"description\":\"Unprocessable Content\",\"content\":{\"application/json\":{\"schema\":{\"type\":\"object\",\"properties\":{\"status\":{\"type\":\"integer\"},\"error\":{\"type\":\"string\"},\"errors\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}}}}}}}}}}}" : String}

# `body` still validates: a body that fails the schema never reaches the
# handler.
law oa_body_validates:
  {Router.dispatch([OpenApi.body(Schema.boolean(), Router.post("/t", noop))],
      Http.Request.with_body(request("POST /t HTTP/1.1\r\ncontent-type: application/json\r"), "5"))
    == IO.pure(Http.Response, Http.Response.with_route(Schema.unprocessable(Schema.errors(Schema.boolean(), Json.of_u32(5))), "/t")) : IO(Http.Response)}

# And a body that matches reaches it.
law oa_body_passes:
  {Router.dispatch([OpenApi.body(Schema.boolean(), Router.post("/t", noop))],
      Http.Request.with_body(request("POST /t HTTP/1.1\r\ncontent-type: application/json\r"), "true"))
    == IO.pure(Http.Response, Http.Response.with_route(Http.Response.empty(204), "/t")) : IO(Http.Response)}

# Route labels
# ------------

law route_pattern_named:
  {Router.render_pattern(Router.parse_pattern("/users/:id/files/*rest")) == "/users/:id/files/*rest" : String}

law route_pattern_root:
  {Router.render_pattern(Router.parse_pattern("/")) == "/" : String}

# A route that runs leaves its pattern, as written, on the response.
law route_on_hit:
  {Router.dispatch([Router.get("/users/:id", noop)], request("GET /users/7 HTTP/1.1\r"))
    == IO.pure(Http.Response, Http.Response.with_route(Http.Response.empty(204), "/users/:id")) : IO(Http.Response)}

law route_mounted:
  {Router.dispatch(Router.mount("/api", [Router.get("/t/:id", noop)]), request("GET /api/t/1 HTTP/1.1\r"))
    == IO.pure(Http.Response, Http.Response.with_route(Http.Response.empty(204), "/api/t/:id")) : IO(Http.Response)}

# HEAD running the GET route is labelled with the GET route.
law route_on_fallback:
  {Router.dispatch([Router.get("/", noop)], request("HEAD / HTTP/1.1\r"))
    == IO.pure(Http.Response, Http.Response.with_route(Http.Response.empty(204), "/")) : IO(Http.Response)}

# No route ran: no label, for 404 and 405 alike.
law route_none_on_404:
  {Router.dispatch([Router.get("/a", noop)], request("GET /b HTTP/1.1\r"))
    == IO.pure(Http.Response, Http.Response.not_found()) : IO(Http.Response)}

law route_none_on_405:
  {Router.dispatch([Router.get("/a", noop)], request("POST /a HTTP/1.1\r"))
    == IO.pure(Http.Response, Http.Response.method_not_allowed("GET, HEAD, OPTIONS")) : IO(Http.Response)}

law route_read:
  {Http.Response.route(Http.Response.with_route(Http.Response.empty(204), "/a")) == "/a" : String}

# `settle` removes the label, so the wire never carries it.
law route_settled:
  {Http.Response.settle(Http.Prod{}, Http.Response.with_route(Http.Response.empty(204), "/a"))
    == Http.Response.empty(204) : Http.Response}

law route_settled_failed:
  {Http.Response.header(Http.Response.settle(Http.Prod{}, Http.Response.with_route(Http.Response.fail(Http.NotFound{"x"}), "/a")), "air-route")
    == "" : String}

# Metrics
# -------

def none() -> Map<&2, String>:
  Map.new(&2, String)

def has.fin(r: Maybe<&2, Text.Two()>) -> Bool:
  match r:
    case Some{kv}:
      True{}
    case None{}:
      False{}

# Whether `s` contains `part`.
def has(+s: String, +part: String) -> Bool:
  has.fin(Text.split_str(s, part))

law m_document:
  {Metrics.expose_text(Metrics.observe("GET", "/a", 200, 3, none()))
    == "# HELP air_http_requests_total Requests answered, by method, route and status.\n# TYPE air_http_requests_total counter\nair_http_requests_total{method=\"GET\",route=\"/a\",status=\"200\"} 1\n# HELP air_http_request_duration_seconds Time in the app, from the middleware's view.\n# TYPE air_http_request_duration_seconds histogram\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"0.005\"} 1\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"0.01\"} 1\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"0.025\"} 1\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"0.05\"} 1\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"0.1\"} 1\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"0.25\"} 1\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"0.5\"} 1\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"1\"} 1\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"2.5\"} 1\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"5\"} 1\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"10\"} 1\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"+Inf\"} 1\nair_http_request_duration_seconds_sum{route=\"/a\"} 0.003\nair_http_request_duration_seconds_count{route=\"/a\"} 1\n" : String}

law m_counter:
  {has(Metrics.expose_text(Metrics.observe("GET", "/a", 200, 3, Metrics.observe("GET", "/a", 200, 4, none()))),
    "air_http_requests_total{method=\"GET\",route=\"/a\",status=\"200\"} 2\n") == True{} : Bool}

# 30 ms counts in 0.05 and above, not in 0.025.
law m_bucket:
  {[has(Metrics.expose_text(Metrics.observe("GET", "/a", 200, 30, none())), "le=\"0.025\"} 0\n"),
    has(Metrics.expose_text(Metrics.observe("GET", "/a", 200, 30, none())), "le=\"0.05\"} 1\n")]
    == [True{}, True{}] : List<&2, Bool>}

# A bound is inclusive: 50 ms is in 0.05.
law m_bucket_edge:
  {[Metrics.bucket(50), Metrics.bucket(51), Metrics.bucket(0), Metrics.bucket(10001)]
    == ["0.05", "0.1", "0.005", "+Inf"] : List<&2, String>}

law m_le:
  {[Metrics.le(5), Metrics.le(10), Metrics.le(250), Metrics.le(1000), Metrics.le(2500), Metrics.le(10000)]
    == ["0.005", "0.01", "0.25", "1", "2.5", "10"] : List<&2, String>}

law m_sum:
  {has(Metrics.expose_text(Metrics.observe("GET", "/a", 200, 1500, Metrics.observe("GET", "/a", 200, 3, none()))),
    "air_http_request_duration_seconds_sum{route=\"/a\"} 1.503\n") == True{} : Bool}

# The milliseconds carry into seconds, so the sum does not wrap at 49 days.
law m_sum_carry:
  {[Text.map_get(Metrics.observe("GET", "/a", 200, 2, Metrics.observe("GET", "/a", 200, 999, none())), "s\t/a", ""),
    Text.map_get(Metrics.observe("GET", "/a", 200, 2, Metrics.observe("GET", "/a", 200, 999, none())), "m\t/a", "")]
    == ["1", "1"] : List<&2, String>}

law m_other:
  {has(Metrics.expose_text(Metrics.observe("BREW", "/a", 200, 1, none())), "method=\"OTHER\"") == True{} : Bool}

law m_escape:
  {has(Metrics.expose_text(Metrics.observe("GET", "/a\"b\\\n", 200, 1, none())), "route=\"/a\\\"b\\\\\\n\"") == True{} : Bool}

law m_unmatched:
  {has(Metrics.expose_text(Metrics.observe("GET", "", 404, 1, none())),
    "air_http_requests_total{method=\"GET\",route=\"\",status=\"404\"} 1\n") == True{} : Bool}

law m_app_counter:
  {has(Metrics.expose_text(Metrics.tally("jobs_done", Metrics.tally("jobs_done", none()))),
    "# TYPE app_jobs_done_total counter\napp_jobs_done_total 2\n") == True{} : Bool}

law m_app_name_checked:
  {[Metrics.tally("Jobs", none()), Metrics.tally("a-b", none()), Metrics.tally("", none())]
    == [none(), none(), none()] : List<&2, Map<&2, String>>}

# The `+Inf` bucket and `_count` agree with the counters' total.
law m_count_matches:
  {has(Metrics.expose_text(Metrics.observe("POST", "/a", 500, 20000, Metrics.observe("GET", "/a", 200, 1, none()))),
    "le=\"10\"} 1\nair_http_request_duration_seconds_bucket{route=\"/a\",le=\"+Inf\"} 2\nair_http_request_duration_seconds_sum{route=\"/a\"} 20.001\nair_http_request_duration_seconds_count{route=\"/a\"} 2\n") == True{} : Bool}

law m_content_type:
  {Http.Response.header(Metrics.exposition(none()), "content-type") == "text/plain; version=0.0.4; charset=utf-8" : String}

# Trace context
# -------------

def tp_trace() -> String:
  "4bf92f3577b34da6a3ce929d0e0e4736"

def tp_parent() -> String:
  "00f067aa0ba902b7"

law tp_valid:
  {Trace.parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
    == Some{Trace.Parent{tp_trace(), tp_parent(), "01"}} : Maybe<&2, Trace.Parent>}

law tp_zero_trace:
  {Trace.parse("00-00000000000000000000000000000000-00f067aa0ba902b7-01") == None{} : Maybe<&2, Trace.Parent>}

law tp_zero_parent:
  {Trace.parse("00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01") == None{} : Maybe<&2, Trace.Parent>}

law tp_upper:
  {Trace.parse("00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01") == None{} : Maybe<&2, Trace.Parent>}

law tp_ff:
  {Trace.parse("ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01") == None{} : Maybe<&2, Trace.Parent>}

# A later version is read by its first four fields.
law tp_future:
  {Trace.parse("01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-extra")
    == Some{Trace.Parent{tp_trace(), tp_parent(), "01"}} : Maybe<&2, Trace.Parent>}

# Version 00 has exactly four.
law tp_00_extra:
  {Trace.parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-extra") == None{} : Maybe<&2, Trace.Parent>}

law tp_short:
  {[Trace.parse("00-4bf92f3577b34da6a3ce929d0e0e473-00f067aa0ba902b7-01"), Trace.parse(""), Trace.parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-1")]
    == [None{}, None{}, None{}] : List<&2, Maybe<&2, Trace.Parent>>}

law tp_render:
  {Trace.render(tp_trace(), tp_parent(), "01") == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" : String}

law tp_sampled_bit:
  {[Trace.is_sampled("01"), Trace.is_sampled("00"), Trace.is_sampled("03"), Trace.is_sampled("02")]
    == [True{}, False{}, True{}, False{}] : List<&2, Bool>}

# Sampling reads the trace id's last eight hex digits: the same trace is
# always kept or always dropped.
law sample_stable:
  {[Trace.keeps(4, "4bf92f3577b34da6a3ce929d00000004"), Trace.keeps(4, "4bf92f3577b34da6a3ce929d00000005"),
    Trace.keeps(1, tp_trace()), Trace.keeps(0, "4bf92f3577b34da6a3ce929d00000004")]
    == [True{}, False{}, True{}, False{}] : List<&2, Bool>}

law span_name:
  {[Trace.span_name("GET", "/users/:id"), Trace.span_name("POST", "")] == ["GET /users/:id", "POST"] : List<&2, String>}

law span_json:
  {Trace.json(Trace.Span{tp_trace(), "a1b2c3d4e5f60718", tp_parent(), "GET /users/:id", "1790000000000", 3, 200, "GET", "/users/:id", "/users/7"})
    == "{\"trace_id\":\"4bf92f3577b34da6a3ce929d0e0e4736\",\"span_id\":\"a1b2c3d4e5f60718\",\"parent_span_id\":\"00f067aa0ba902b7\",\"name\":\"GET /users/:id\",\"start_time_unix_ms\":1790000000000,\"duration_ms\":3,\"http.request.method\":\"GET\",\"http.route\":\"/users/:id\",\"url.path\":\"/users/7\",\"http.response.status_code\":200}" : String}

# The downstream value carries this span's id, not the caller's.
law tp_locals:
  {Http.Request.local(Trace.with_ids(request("GET / HTTP/1.1\r"), Trace.Ids{tp_trace(), "a1b2c3d4e5f60718", tp_parent(), "01"}), "traceparent")
    == "00-4bf92f3577b34da6a3ce929d0e0e4736-a1b2c3d4e5f60718-01" : String}

