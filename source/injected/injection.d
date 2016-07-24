module injected.injection;

import std.meta : staticMap, Filter;

import injected.resolver : Resolver;

/**
 * Annotation for an injection.
 * It can optionally include a name to use for the lookup.
 */
struct Injected(T, string _name = null) {
    alias Type = T;
    enum name = _name;
}

/**
 * Annotation marking a class or factory function as
 * Injectable. The
 */
struct Injectable(T...) {
    /**
     * A tuple of the Injections
     */
    alias Injections = T;
}

template getInjectables(alias symbol) {
    private template isInjectable(alias T) {
        enum isInjectable = is(T: Injectable!(U), U...);
    }

    alias getInjectables = Filter!(isInjectable, __traits(getAttributes, symbol));
}

template toInjected(T) {
    static if (is(T: Injected!U, U) || is(T: Injected!(U, n), U, string n)) {
        alias toInjected = T;
    } else {
        alias toInjected = Injected!T;
    }
}

/**
 * Take an AliasSeq of types and/or `Injected` values and return
 * a ValueSeq of `Injected` values, where any Types are converted to
 * nameless `Injected` values for that type.
 */
template extractInjected(Args...) {
    alias extractInjected = staticMap!(toInjected, Args);
}

///
unittest {
    import std.meta : AliasSeq;

    static assert(is(extractInjected!(int, string) == AliasSeq!(Injected!int, Injected!string)));
    static assert(is(extractInjected!(Injected!float) == AliasSeq!(Injected!float)));
    static assert(is(extractInjected!(Injected!(int, "foo")) == AliasSeq!(Injected!(int, "foo"))));

    static assert(is(extractInjected!(Injected!(string, "name"), int, Injected!(void*)) == AliasSeq!(Injected!(string, "name"), Injected!int, Injected!(void*))));

    static assert(!__traits(compiles, extractInjected!("hi", int)));
}

alias InjectionType(T) = toInjected!T.Type;

auto injectionSeq(Args...)(Resolver resolver) {
    import std.typecons : Tuple;
    alias InjectionTypes = staticMap!(InjectionType, Args);

    Tuple!(InjectionTypes) injections;
    foreach (i, injected; extractInjected!Args) {
        alias T = InjectionType!injected;
        static if (injected.name is null) {
            injections[i] = resolver.resolve!T();
        } else {
            injections[i] = resolver.resolve!T(injected.name);
        }
    }
    return injections;
}

unittest {
    import std.meta : AliasSeq;
    import std.typecons : tuple;
    import injected.container;

    auto container = makeContainer();
    container.value!int("a", 10);
    container.value!int("b", 20);
    container.value!string("name");
    container.value!float(3.14f);


    assert(injectionSeq!(Injected!string)(container) == tuple("name"));
    assert(injectionSeq!(Injected!int)(container) == tuple(10));
    assert(injectionSeq!(Injected!(int, "a"))(container) == tuple(10));
    assert(injectionSeq!(Injected!(int,"b"))(container) == tuple(20));
    assert(injectionSeq!(int, string, float)(container) == tuple(10, "name", 3.14f));

    assert(injectionSeq!(Injected!string, Injected!(int, "b"), Injected!float)(container) ==
           tuple("name", 20, 3.14f));
}
