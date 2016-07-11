module injected.injection;

import std.meta : staticMap;

import injected.resolver : Resolver;

/**
 * Annotation for an injection.
 * It can optionally include a name to use for the lookup.
 *
 * Notes: Using a value with a null name, and using the type itself
 * as the annotation are equivalent for the purposes of the injected library.
 */
struct Injected(T) {
    string name = null;
    alias Type = T;
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

template toInjected(Args...) if (Args.length == 1) {
    import std.meta : Alias;
    private alias T = Alias!(Args[0]);

    static if (is(T: Injected!U, U)) {
        enum toInjected = T();
    } else static if (is(T)) {
        enum toInjected = Injected!T();
    } else static if (is(typeof(T) : Injected!U, U)) {
        enum toInjected = T;
    } else {
        static assert(0, "Injection must be a type or an instance of Injectable.");
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

    static assert(extractInjected!(int, string) == AliasSeq!(Injected!int(), Injected!string()));
    static assert(extractInjected!(Injected!float) == AliasSeq!(Injected!float()));
    static assert(extractInjected!(Injected!int("foo")) == AliasSeq!(Injected!int("foo")));

    static assert(extractInjected!(Injected!string("name"), int, Injected!(void*)) == AliasSeq!(Injected!string("name"), Injected!int(), Injected!(void*)()));

    static assert(!__traits(compiles, extractInjected!("hi", int)));
}

template InjectionType(Args...) if (Args.length == 1) {
    static if (is(typeof(Args[0]) T: Injected!T)) {
        alias InjectionType = T;
    } else static if (is(Args[0] T: Injected!T)) {
        alias InjectionType = T;
    } else static if (is(Args[0] T)) {
        alias InjectionType = T;
    } else {
        alias InjectionType = typeof(Args[0]);
    }

}

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
    assert(injectionSeq!(Injected!int("a"))(container) == tuple(10));
    assert(injectionSeq!(Injected!int("b"))(container) == tuple(20));
    assert(injectionSeq!(int, string, float)(container) == tuple(10, "name", 3.14f));

    assert(injectionSeq!(Injected!string, Injected!int("b"), Injected!float())(container) ==
           tuple("name", 20, 3.14f));
}
