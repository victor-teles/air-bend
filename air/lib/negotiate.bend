import Base
import ./text.bend as Text

# Negotiate
# =========
#
# One algorithm for `Accept`, `Accept-Encoding`, `Accept-Language` and
# `Accept-Charset` (RFC 9110 §12.4.2): each offer takes the q of the
# most specific range that matches it, and the offer with the highest
# q wins, the earliest on ties. q is kept in thousandths, so `q=0.8` is
# 800: Bend has no float parser, and only the order matters.

# One range and its quality: "text/*;q=0.5" is Pref{"text/*", 500}.
type Pref is Data:
  Pref{range: String, q: U32}

# Quality
# -------

def int_part(+s: String) -> Maybe<&2, U32>:
  match s:
    case SNil{}:
      Some{0}
    case SCon{h, t}:
      Text.digits(s)

# The fraction padded or cut to three digits: "5" is 500.
def frac_part(s: String) -> Maybe<&2, U32>:
  Text.digits(String.take(s ++ "000", 3n))

def q_of(int: Maybe<&2, U32>, frac: Maybe<&2, U32>) -> U32:
  match int frac:
    case Some{i} Some{f}:
      Bool.pick(U32, U32.is_ge(i, 1), 1000, f)
    case _ _:
      0

# "1", "0.8", ".5" in thousandths; anything malformed is 0.
def thousandths(+s: String) -> U32:
  q_of(int_part(Text.fst(Text.split_at(s, '.'))), frac_part(Text.snd(Text.split_at(s, '.'))))

def q_param.pick(v: String, is_q: Bool, +found: U32) -> U32:
  match is_q:
    case True{}:
      thousandths(v)
    case False{}:
      found

def q_param.try(+found: U32, kv: Text.Two()) -> U32:
  (k, v) = kv
  q_param.pick(String.trim(v), String.eq(String.to_lower(String.trim(k)), "q"), found)

# The q among a range's parameters; 1000 when absent.
def q_param(params: List<&2, String>, +found: U32) -> U32:
  match params:
    case Nil{}:
      found
    case Con{+h, t}:
      q_param(t, q_param.try(found, Text.split_at(h, '=')))

# Parsing
# -------

def pref(pieces: List<&2, String>) -> Pref:
  match pieces:
    case Nil{}:
      Pref{SNil{}, 0}
    case Con{range, params}:
      Pref{String.to_lower(String.trim(range)), q_param(params, 1000)}

def parse.go(items: List<&2, String>, acc: List<&2, Pref>) -> List<&2, Pref>:
  match items:
    case Nil{}:
      List.reverse(&2, Pref, acc)
    case Con{+h, t}:
      parse.go(t, Con{pref(Text.split_all(h, ';')), acc})

# The ranges of an Accept-style header value, in order; an empty range
# (from a stray comma) is kept and matches nothing.
def parse(+v: String) -> List<&2, Pref>:
  parse.go(Text.split_all(v, ','), Nil{})

# Matching
# --------

def drop_last(s: String) -> String:
  String.reverse(String.drop(String.reverse(s), 1n))

# How well a range fits an offer: 0 for no match, 1 for `*`, 2 for a
# partial match (`text/*`, or `en` against `en-us` when `lang`), 3 for
# an exact one.
def specificity.pick(exact: Bool, star: Bool, partial: Bool) -> U32:
  match exact star partial:
    case True{} _ _:
      3
    case False{} True{} _:
      1
    case False{} False{} True{}:
      2
    case False{} False{} False{}:
      0

def partial_match(+range: String, +offer: String, lang: Bool) -> Bool:
  match lang:
    case True{}:
      String.starts_with(offer, range ++ "-")
    case False{}:
      Bool.and(String.ends_with(range, "/*"), String.starts_with(offer, drop_last(range)))

def specificity(+range: String, +offer: String, lang: Bool) -> U32:
  specificity.pick(
    String.eq(range, offer),
    Bool.or(String.eq(range, "*"), String.eq(range, "*/*")),
    Bool.and(Text.non_empty(range), partial_match(range, offer, lang)))

# The best match so far for one offer: its specificity and q.
type Best is Data:
  Best{spec: U32, q: U32}

def better(cur: Best, +spec: U32, +q: U32, gt: Bool) -> Best:
  match gt:
    case True{}:
      Best{spec, q}
    case False{}:
      cur

def best.step(cur: Best, +spec: U32, +q: U32) -> Best:
  match cur:
    case Best{+s, q0}:
      better(Best{s, q0}, spec, q, U32.is_gt(spec, s))

def best.go(prefs: List<&2, Pref>, +offer: String, +lang: Bool, cur: Best) -> Best:
  match prefs:
    case Nil{}:
      cur
    case Con{Pref{+range, +q}, t}:
      best.go(t, offer, lang, best.step(cur, specificity(range, offer, lang), q))

def best_q(best: Best) -> U32:
  match best:
    case Best{s, q}:
      q

# The q an offer earns: that of the most specific matching range, the
# first on ties; 0 when nothing matches.
def offer_q(prefs: List<&2, Pref>, +offer: String, lang: Bool) -> U32:
  best_q(best.go(prefs, offer, lang, Best{0, 0}))

def choose.step(offer: String, +q: U32, cur: Maybe<&2, String>, +cur_q: U32, gt: Bool) -> Maybe<&2, String>:
  match gt:
    case True{}:
      Some{offer}
    case False{}:
      cur

def choose.go(offers: List<&2, String>, +prefs: List<&2, Pref>, +lang: Bool, cur: Maybe<&2, String>, +cur_q: U32) -> Maybe<&2, String>:
  match offers:
    case Nil{}:
      cur
    case Con{+offer, t}:
      +q = offer_q(prefs, offer, lang)
      choose.go(t, prefs, lang, choose.step(offer, q, cur, cur_q, U32.is_gt(q, cur_q)), U32.max(q, cur_q))

def pick.go(+v: String, offers: List<&2, String>, lang: Bool, absent: Bool) -> Maybe<&2, String>:
  match absent:
    case True{}:
      List.head(&2, String, offers)
    case False{}:
      choose.go(offers, parse(v), lang, None{}, 0)

# The offer the header value prefers, or None when it accepts none of
# them. An absent (empty) header accepts everything, so the first offer
# wins. `lang` turns on the language prefix rule (`en` matches `en-us`).
def pick(+v: String, offers: List<&2, String>, lang: Bool) -> Maybe<&2, String>:
  pick.go(v, offers, lang, String.is_empty(String.trim(v)))
