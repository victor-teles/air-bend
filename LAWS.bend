import Base
import ./air/text.bend as Text
import ./air/chunk.bend as Chunk
import ./air/http.bend as Http
import ./air/router.bend as Router
import ./air/race.bend as Race
import ./air/drain.bend as Drain
import ./air/server.bend as Server

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
      Http.Request{Http.GET{}, "HTTP/1.1", "/", "/", Map.new(&2, String), Map.new(&2, String), Map.new(&2, String), ""}

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
