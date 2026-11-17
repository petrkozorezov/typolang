"""Disposable sufficiency experiment; neither typolang syntax nor its runtime.

Kernel: finite structural patterns, capture-preserving template instantiation,
fresh template declarations, ordered root rewriting, and a step budget.
The guest machine below contains no Python callbacks. It observes WHNF, not HNF,
and implements call-by-name, not memoized call-by-need.
"""
from dataclasses import dataclass
from itertools import count
import unittest


@dataclass(frozen=True)
class Id:
    text: str
    serial: int = 0


@dataclass(frozen=True)
class Pair:
    left: object
    right: object


@dataclass(frozen=True)
class Ref:
    target: object


@dataclass(frozen=True)
class Def:
    label: object
    body: object


serials = count(1)
NIL = Id("nil")
DONE = Id("done")
KEEP = Id("keep")
RUN = Id("run")


def fresh(text):
    return Id(text, next(serials))


def seq(*items):
    result = NIL
    for item in reversed(items):
        result = Pair(item, result)
    return result


def term(tag, *fields):
    return Pair(Id(tag), seq(*fields))


def fields(t, tag):
    if not isinstance(t, Pair) or t.left != Id(tag):
        return None
    result, rest = [], t.right
    while isinstance(rest, Pair):
        result.append(rest.left)
        rest = rest.right
    return tuple(result) if rest == NIL else None


def v(name):
    return term("$capture", Id(name))


def same(name):
    return term("$same-id", Id(name))


def atom(name):
    return term("$id", Id(name))


def match(pattern, subject, bindings=None):
    """Only finite syntax: Ref is inspected, never followed here."""
    bindings = {} if bindings is None else bindings
    capture = fields(pattern, "$capture")
    identity = fields(pattern, "$same-id")
    id_pattern = fields(pattern, "$id")
    if capture is not None or id_pattern is not None:
        name = (capture or id_pattern)[0]
        if id_pattern is not None and not isinstance(subject, Id):
            return None
        if name in bindings:
            raise ValueError("use an explicit identity test, not a repeated capture")
        return bindings | {name: subject}
    if identity is not None:
        expected = bindings[identity[0]]
        if not isinstance(expected, Id):
            raise ValueError("this experiment only compares identities")
        return bindings if subject == expected else None
    if type(pattern) is not type(subject):
        return None
    if isinstance(pattern, Id):
        return bindings if pattern == subject else None
    if isinstance(pattern, Ref):
        return match(pattern.target, subject.target, bindings)
    if isinstance(pattern, (Pair, Def)):
        names = ("left", "right") if isinstance(pattern, Pair) else ("label", "body")
        for name in names:
            bindings = match(getattr(pattern, name), getattr(subject, name), bindings)
            if bindings is None:
                return None
        return bindings
    raise TypeError(pattern)


def instantiate(template, bindings, renames=None):
    """Captured fragments are inserted intact, never traversed or re-resolved."""
    renames = {} if renames is None else renames
    capture = fields(template, "$capture")
    if capture is not None:
        return bindings[capture[0]]
    if isinstance(template, Id):
        return template
    if isinstance(template, Ref):
        if isinstance(template.target, Id):
            return Ref(renames.get(template.target, template.target))
        return Ref(instantiate(template.target, bindings, renames))
    if isinstance(template, Pair):
        return Pair(instantiate(template.left, bindings, renames),
                    instantiate(template.right, bindings, renames))
    if isinstance(template, Def):
        if isinstance(template.label, Id):
            label = fresh(template.label.text)
            renames = renames | {template.label: label}
        else:
            label = instantiate(template.label, bindings, renames)
        return Def(label, instantiate(template.body, bindings, renames))
    raise TypeError(template)


def rule(pattern, replacement):
    return term("rule", pattern, replacement)


class Budget(Exception):
    pass


class Machine:
    def __init__(self, rules):
        self.rules = tuple(rules)
        self.steps = 0

    def run(self, expression, budget=2000):
        for _ in range(budget):
            for encoded in self.rules:
                pattern, replacement = fields(encoded, "rule")
                bindings = match(pattern, expression)
                if bindings is not None:
                    expression = instantiate(replacement, bindings)
                    self.steps += 1
                    break
            else:
                return expression
        raise Budget


# All helpers below only construct terms. Their names have no kernel meaning.
T = term
E = lambda t, env, k: T("eval", t, env, k)
R = lambda value, k: T("return", value, k)
S = lambda t, env: T("suspension", t, env)
F = lambda s, k: T("force", s, k)
C = lambda scope, env: T("closure", scope, env)
L = lambda key, env, k: T("lookup", key, env, k)
B = lambda scope, args, caller, env, mode, k: T("bind", scope, args, caller, env, mode, k)


def lam(params, body):
    scope = T("body", body)
    for p in reversed(params):
        scope = Def(p, scope)
    return T("lambda", scope)


def app(f, *args):
    return T("call", f, seq(*args))


def quote(t):
    return T("quote", t)


def unquote(t):
    return T("unquote", t)


x, y, a, rest, body, env, caller, k, value, scope, args, mode, h, tail = map(
    v, "x y a rest body env caller k value scope args mode h tail".split())

LIBRARY = [
    rule(F(S(body, env), k), E(body, env, k)),
    rule(E(Ref(x), env, k), L(x, env, k)),
    rule(L(x, Pair(Pair(same("x"), value), rest), k), F(value, k)),
    rule(L(x, Pair(Pair(y, value), rest), k), L(x, rest, k)),
    rule(L(x, T("recursive-env", same("x"), body, env), k),
         E(body, T("recursive-env", x, body, env), k)),
    rule(L(x, T("recursive-env", y, body, env), k), L(x, env, k)),
    rule(L(x, NIL, k), R(T("open", Ref(x)), k)),
    rule(E(Def(x, body), env, k), E(body, T("recursive-env", x, body, env), k)),
    rule(E(T("lambda", scope), env, k), R(C(scope, env), k)),
    rule(E(T("call", a, args), env, k), E(a, env, T("apply-k", args, env, RUN, k))),
    rule(E(T("bind-code", a, args), env, k), E(a, env, T("apply-k", args, env, KEEP, k))),
    rule(R(C(scope, env), T("apply-k", args, caller, mode, k)),
         B(scope, args, caller, env, mode, k)),
    rule(R(T("open", a), T("apply-k", args, caller, mode, k)),
         R(T("open", T("call-residual", a, S(args, caller))), k)),
    rule(R(value, T("apply-k", args, caller, mode, k)), R(T("error", Id("not-function")), k)),
    rule(B(Def(x, rest), Pair(a, args), caller, env, mode, k),
         B(rest, args, caller, Pair(Pair(x, S(a, caller)), env), mode, k)),
    rule(B(Def(x, rest), NIL, caller, env, mode, k), R(C(Def(x, rest), env), k)),
    rule(B(T("body", body), NIL, caller, env, KEEP, k), R(S(body, env), k)),
    rule(B(T("body", body), NIL, caller, env, RUN, k), E(body, env, k)),
    rule(B(T("body", body), Pair(a, rest), caller, env, mode, k),
         R(T("error", Id("extra-argument")), k)),
    rule(E(T("cons", h, tail), env, k), R(T("cell", S(h, env), S(tail, env)), k)),
    rule(E(T("head", a), env, k), E(a, env, T("head-k", k))),
    rule(E(T("tail", a), env, k), E(a, env, T("tail-k", k))),
    rule(R(T("cell", h, tail), T("head-k", k)), F(h, k)),
    rule(R(T("cell", h, tail), T("tail-k", k)), F(tail, k)),
    rule(E(quote(a), env, k), R(S(a, env), k)),
    rule(E(unquote(a), env, k), E(a, env, T("unquote-k", k))),
    rule(R(S(a, env), T("unquote-k", k)), E(a, env, k)),
    rule(E(T("value", value), env, k), R(value, k)),
    rule(E(atom("a"), env, k), R(a, k)),
]

# Interpreted matching. Structural Ref matching above is always decidable;
# matching its observed value can be pending. These are separate operations.
NO, WAIT, FAULT = Id("no-match"), Id("pending"), Id("match-error")
p, q, s, clauses, left, right, e1, e2 = map(v, "p q s clauses left right e1 e2".split())
P = lambda pattern, subject, k: T("probe", pattern, subject, k)
CH = lambda clauses, subject, env, k: T("choose", clauses, subject, env, k)
YES = lambda bindings: T("matched", bindings)
APPEND = lambda left, right, k: T("append", left, right, k)

LIBRARY += [
    rule(APPEND(NIL, right, k), R(right, k)),
    rule(APPEND(Pair(h, tail), right, k), APPEND(tail, right, T("prepend-k", h, k))),
    rule(R(rest, T("prepend-k", h, k)), R(Pair(h, rest), k)),
    rule(E(T("case", a, clauses), env, k), CH(clauses, S(a, env), env, k)),
    rule(CH(Pair(Pair(p, body), rest), s, env, k), P(p, s, T("choose-k", p, body, rest, s, env, k))),
    rule(CH(NIL, s, env, k), R(T("error", Id("no-branch")), k)),
    rule(R(YES(left), T("choose-k", p, body, rest, s, env, k)),
         APPEND(left, env, T("branch-env-k", body, k))),
    rule(R(env, T("branch-env-k", body, k)), E(body, env, k)),
    rule(R(NO, T("choose-k", p, body, rest, s, env, k)), CH(rest, s, env, k)),
    rule(R(WAIT, T("choose-k", p, body, rest, s, env, k)),
         R(T("open", T("match-residual", s, Pair(Pair(p, body), rest), env)), k)),
    rule(R(FAULT, T("choose-k", p, body, rest, s, env, k)), R(T("error", Id("matching")), k)),
    rule(P(T("capture", x), s, k), R(YES(seq(Pair(x, s))), k)),
    rule(P(Id("wildcard"), s, k), R(YES(NIL), k)),
    rule(P(T("literal", x), s, k), F(s, T("literal-k", x, k))),
    rule(R(atom("a"), T("literal-k", same("a"), k)), R(YES(NIL), k)),
    rule(R(T("open", a), T("literal-k", x, k)), R(WAIT, k)),
    rule(R(T("error", a), T("literal-k", x, k)), R(FAULT, k)),
    rule(R(value, T("literal-k", x, k)), R(NO, k)),
    rule(P(T("pair-pattern", p, q), s, k), F(s, T("pair-pattern-k", p, q, k))),
    rule(R(T("cell", h, tail), T("pair-pattern-k", p, q, k)), P(p, h, T("left-probe-k", q, tail, k))),
    rule(R(T("open", a), T("pair-pattern-k", p, q, k)), R(WAIT, k)),
    rule(R(T("error", a), T("pair-pattern-k", p, q, k)), R(FAULT, k)),
    rule(R(value, T("pair-pattern-k", p, q, k)), R(NO, k)),
    rule(R(left, T("left-probe-k", q, tail, k)), P(q, tail, T("right-probe-k", left, k))),
    rule(R(right, T("right-probe-k", left, k)), T("combine", left, right, k)),
    rule(T("combine", NO, right, k), R(NO, k)),
    rule(T("combine", left, NO, k), R(NO, k)),
    rule(T("combine", WAIT, right, k), R(WAIT, k)),
    rule(T("combine", left, WAIT, k), R(WAIT, k)),
    rule(T("combine", FAULT, right, k), R(FAULT, k)),
    rule(T("combine", left, FAULT, k), R(FAULT, k)),
    rule(T("combine", YES(e1), YES(e2), k), APPEND(e1, e2, T("both-matched-k", k))),
    rule(R(env, T("both-matched-k", k)), R(YES(env), k)),
]


def observe(expr, extra=(), budget=2000):
    result = Machine(tuple(extra) + tuple(LIBRARY)).run(E(expr, NIL, DONE), budget)
    returned = fields(result, "return")
    if returned is None or returned[1] != DONE:
        raise AssertionError(("unexpected stuck machine", result))
    return returned[0]


def free(term_, bound=frozenset()):
    """Independent inspection oracle; never called by the guest evaluator."""
    if isinstance(term_, Id):
        return frozenset()
    if isinstance(term_, Ref):
        return frozenset({term_.target}) - bound
    if isinstance(term_, Def):
        return free(term_.body, bound | {term_.label})
    return free(term_.left, bound) | free(term_.right, bound)


class Checks(unittest.TestCase):
    def setUp(self):
        self.x, self.y, self.h = fresh("x"), fresh("y"), fresh("hole")
        self.a, self.b = Id("a"), Id("b")

    def test_holes_need_no_preanalysis(self):
        expr = Pair(Ref(self.h), Ref(self.h))
        self.assertEqual(free(expr), {self.h})
        self.assertEqual(observe(Ref(self.h)), T("open", Ref(self.h)))
        self.assertEqual(observe(app(lam([self.x, self.y], Ref(self.x)), self.a, Ref(self.h))), self.a)

    def test_lambda_scopes_remove_bound_free_references(self):
        self.assertEqual(free(lam([self.x], Pair(Ref(self.x), Ref(self.h)))), {self.h})

    def test_free_input_still_open_when_used(self):
        self.assertEqual(observe(app(lam([self.x], Ref(self.x)), Ref(self.h))), T("open", Ref(self.h)))

    def test_full_binding_does_not_execute_body(self):
        fn = lam([self.x], app(self.a))
        bound = observe(T("bind-code", fn, seq(self.b)))
        self.assertIsNotNone(fields(bound, "suspension"))
        self.assertEqual(observe(unquote(T("value", bound))), T("error", Id("not-function")))

    def test_partial_binding_and_independent_invocations(self):
        fn = lam([self.x, self.y], Ref(self.y))
        partial = observe(T("bind-code", fn, seq(self.a)))
        self.assertEqual(observe(app(T("value", partial), self.a)), self.a)
        self.assertEqual(observe(app(T("value", partial), self.b)), self.b)
        self.assertEqual(observe(app(fn, self.b, self.a)), self.a)

    def test_fixed_arity_is_not_currying(self):
        fn = lam([self.x], lam([self.y], Ref(self.y)))
        self.assertEqual(observe(app(fn, self.a, self.b)), T("error", Id("extra-argument")))

    def test_quote_survives_return_and_identity(self):
        divergent = Def(self.x, Ref(self.x))
        held = observe(app(lam([self.y], Ref(self.y)), quote(divergent)))
        self.assertEqual(held, S(divergent, NIL))
        with self.assertRaises(Budget):
            observe(unquote(T("value", held)), budget=100)

    def test_quote_captures_original_binding(self):
        make = lam([self.x], quote(lam([self.y], Ref(self.x))))
        first = observe(app(make, self.a))
        second = observe(app(make, self.b))
        self.assertEqual(observe(app(unquote(T("value", first)), self.b)), self.a)
        self.assertEqual(observe(app(unquote(T("value", second)), self.a)), self.b)

    def test_recursion_is_finite_and_productive(self):
        stream = Def(self.x, T("cons", self.a, Ref(self.x)))
        self.assertEqual(free(stream), set())
        cursor = stream
        for _ in range(8):
            self.assertEqual(observe(T("head", cursor)), self.a)
            cursor = T("tail", cursor)
        topology = Def(v("label"), T("cons", v("first"), Ref(same("label"))))
        self.assertIsNotNone(match(topology, stream))
        self.assertIsNone(match(topology, Def(self.x, T("cons", self.a, Ref(self.y)))))

    def test_same_spelling_is_not_same_input(self):
        other = fresh("x")
        self.assertNotEqual(self.x, other)
        self.assertEqual(free(Pair(Ref(self.x), Ref(other))), {self.x, other})
        self.assertEqual(observe(app(lam([other], Ref(self.x)), self.a)), T("open", Ref(self.x)))

    def test_template_freshens_new_binders_but_not_inserted_links(self):
        label = fresh("x")
        pattern, replacement = v("fragment"), Def(label, Pair(Ref(label), v("fragment")))
        captured = Ref(label)
        first = instantiate(replacement, match(pattern, captured))
        second = instantiate(replacement, match(pattern, captured))
        self.assertNotEqual(first.label, second.label)
        self.assertEqual(first.body.left, Ref(first.label))
        self.assertIs(first.body.right, captured)
        self.assertEqual(free(first), {label})

    def test_building_ref_from_captured_identity_preserves_target(self):
        label = fresh("local")
        template = Def(label, Pair(Ref(label), Ref(v("external"))))
        copied = instantiate(template, {Id("external"): label})
        self.assertEqual(copied.body.left, Ref(copied.label))
        self.assertEqual(copied.body.right, Ref(label))

    def test_rule_priority_and_nil_success(self):
        first = rule(T("choose", Id("yes")), NIL)
        fallback = rule(T("choose", v("anything")), self.b)
        self.assertEqual(Machine([first, fallback]).run(T("choose", Id("yes"))), NIL)
        self.assertEqual(Machine([first, fallback]).run(T("choose", Id("no"))), self.b)

    def test_interpreter_extension_is_an_ordinary_rule(self):
        extension = rule(E(T("discard-second", a, rest), env, k), E(a, env, k))
        self.assertEqual(observe(T("discard-second", self.a, Ref(self.h)), [extension]), self.a)

    def test_structural_edit_is_a_guest_rule(self):
        edit = [
            rule(E(T("duplicate-body", a), env, k), E(a, env, T("edit-k", k))),
            rule(R(S(T("lambda", Def(x, T("body", T("cons", Ref(same("x")), NIL)))), env), T("edit-k", k)),
                 R(S(T("lambda", Def(x, T("body", T("cons", Ref(x), T("cons", Ref(x), NIL))))), env), k)),
        ]
        fn = lam([self.x], T("cons", Ref(self.x), NIL))
        rewritten = unquote(T("duplicate-body", quote(fn)))
        called = app(rewritten, self.a)
        self.assertEqual(observe(T("head", called), edit), self.a)
        self.assertEqual(observe(T("head", T("tail", called)), edit), self.a)
        self.assertEqual(observe(T("tail", T("tail", called)), edit), NIL)
        self.assertEqual(observe(T("tail", app(fn, self.a))), NIL)

    def test_unknown_match_does_not_select_fallback(self):
        clauses = seq(Pair(T("literal", self.a), self.a), Pair(Id("wildcard"), self.b))
        fn = lam([self.x], T("case", Ref(self.x), clauses))
        self.assertIsNotNone(fields(observe(app(fn, Ref(self.h))), "open"))
        self.assertEqual(observe(app(fn, self.a)), self.a)
        self.assertEqual(observe(app(fn, self.b)), self.b)

    def test_lazy_capture_in_pattern(self):
        clauses = seq(Pair(T("capture", self.x), self.a))
        loop = Def(self.y, Ref(self.y))
        self.assertEqual(observe(T("case", loop, clauses)), self.a)

    def test_rule_functions_compose_through_fallback(self):
        captured = fresh("captured")
        case = lambda subject, *pairs: T("case", subject, seq(*pairs))
        fallback = lam([self.y], case(Ref(self.y), Pair(T("literal", self.b), NIL), Pair(Id("wildcard"), self.b)))
        outer = lam([self.x], case(Ref(self.x), Pair(T("literal", self.a), self.a),
                                   Pair(T("capture", captured), app(fallback, Ref(captured)))))
        self.assertEqual(observe(app(outer, self.a)), self.a)
        self.assertEqual(observe(app(outer, self.b)), NIL)
        self.assertEqual(observe(app(outer, NIL)), self.b)

    def test_known_mismatch_dominates_pending_and_error(self):
        pattern = T("pair-pattern", T("literal", self.a), T("literal", self.a))
        clauses = seq(Pair(pattern, self.a), Pair(Id("wildcard"), self.b))
        for unknown in (Ref(self.h), app(self.a)):
            for first, second in ((unknown, self.b), (self.b, unknown)):
                self.assertEqual(observe(T("case", T("cons", first, second), clauses)), self.b)

    def test_pending_delays_error(self):
        pattern = T("pair-pattern", T("literal", self.a), T("literal", self.a))
        clauses = seq(Pair(pattern, self.a), Pair(Id("wildcard"), self.b))
        for first, second in ((app(self.a), Ref(self.h)), (Ref(self.h), app(self.a))):
            self.assertIsNotNone(fields(observe(T("case", T("cons", first, second), clauses)), "open"))
        self.assertEqual(observe(T("case", T("cons", self.a, app(self.a)), clauses)), T("error", Id("matching")))

    def test_unknown_call_result_does_not_select_fallback(self):
        clauses = seq(Pair(T("literal", self.a), self.a), Pair(Id("wildcard"), self.b))
        self.assertIsNotNone(fields(observe(T("case", app(Ref(self.h), self.a), clauses)), "open"))

    def test_edit_preserves_external_capture(self):
        edit = [
            rule(E(T("duplicate-capture", a), env, k), E(a, env, T("edit-capture-k", k))),
            rule(R(S(T("lambda", Def(y, T("body", T("cons", Ref(x), NIL)))), env), T("edit-capture-k", k)),
                 R(S(T("lambda", Def(y, T("body", T("cons", Ref(x), T("cons", Ref(x), NIL))))), env), k)),
        ]
        make = lam([self.x], quote(lam([self.y], T("cons", Ref(self.x), NIL))))
        saved = observe(app(make, self.a))
        changed = unquote(T("duplicate-capture", T("value", saved)))
        invoked = app(changed, self.b)
        self.assertEqual(observe(T("head", invoked), edit), self.a)
        self.assertEqual(observe(T("head", T("tail", invoked)), edit), self.a)
        original = app(unquote(T("value", saved)), self.b)
        self.assertEqual(observe(T("tail", original)), NIL)


if __name__ == "__main__":
    unittest.main(verbosity=2)
