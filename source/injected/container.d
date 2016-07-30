module injected.container;

import std.traits : isCallable;
import std.typecons : Flag, Yes, No;

import injected.resolver;
import injected.provider;

/**
 * A dependency injection container.
 *
 * Providers are registered with a `TypeInfo` and an optional name.
 * Values can then be resolved using the `TypeInfo` and name.
 */
interface Container : Resolver {
    /**
     * Register a `Provider` for it's `TypeInfo`. A name can also be provided
     * to disambiguate when multiple providers are needed
     *
     * Notes: `provider.providedType` should be a subType of the type represented by `TypeInfo`.
     */
    protected void addProvider(TypeInfo type, Provider provider);
    /// ditto
    protected void addProvider(TypeInfo type, string name, Provider provider);

    /**
     * Register a single value.
     *
     * A `ValueProvider` is used to provide the value.
     */
    final void value(T)(string name, T value) {
        addProvider(typeid(T), name, new ValueProvider!T(value));
    }

    /// ditto
    final void value(T)(T value) {
        addProvider(typeid(T), new ValueProvider!T(value));
    }

    /**
     * Register a Class.
     *
     * Instances are provided using a `ClassProvider` that injects dependencies using
     * this container.
     */
    final void register(I, C: I = I)(Flag!"asSingleton" asSingleton = Yes.asSingleton)  if (is(C == class)) {
        addProvider(typeid(I), maybeSingleton(new ClassProvider!C(this), asSingleton));
    }
    /// ditto
    final void register(I, C: I = I)(string name, Flag!"asSingleton" asSingleton = Yes.asSingleton) if (is(C == class)) {
        addProvider(typeid(I), name, maybeSingleton(new ClassProvider!C(this), asSingleton));
    }

    /**
     * Register a factory function for a type.
     */
    final void factory(T, alias F)(Flag!"asSingleton" asSingleton = Yes.asSingleton) if (isCallable!F && is(ReturnType!F: T)) {
        addProvider(typeid(T), maybeSingleton(new FactoryProvider!F(this), asSingleton));
    }
    /// ditto
    final void factory(T, alias F)(string name, Flag!"asSingleton" asSingleton = Yes.asSingleton) if (isCallable!F && is(ReturnType!F: T)) {
        addProvider(typeid(T), name, maybeSingleton(new FactoryProvider!F(this), asSingleton));
    }

    /// ditto
    final void factory(T, F)(F func, Flag!"asSingleton" asSingleton = Yes.asSingleton) if ((is(F == delegate) || is(F == function)) && is(ReturnType!F: T)) {
        addProvider(typeid(T), maybeSingleton(new FactoryProvider!F(this, func), asSingleton));
    }
    /// ditto
    final void factory(T, F)(string name, F func, Flag!"asSingleton" asSingleton = Yes.asSingleton) if ((is(F == delegate) || is(F == function)) && is(ReturnType!F: T)) {
        addProvider(typeid(T), name, maybeSingleton(new FactoryProvider!F(this, func), asSingleton));
    }

    /**
     * Register a provider using the type returned by `provider.providedType`.
     */
    final void provider(Provider provider) {
        addProvider(provider.providedType, provider);
    }
    /// ditto
    final void provider(string name, Provider provider) {
        addProvider(provider.providedType, name, provider);
    }

    private Provider maybeSingleton(Provider provider, Flag!"asSingleton" asSingleton) pure nothrow {
        if (asSingleton) {
            return new SingletonProvider(provider);
        } else {
            return provider;
        }
    }
}

/**
 * A simple implementation of `Container`.
 *
 * `SimpleContainer` stores providers keyed by the `TypeInfo` and name, in that order.
 * The container itself is registered, so that it can be injected as a dependency into
 * other objects.
 */
class SimpleContainer : Container {

    pure this() {
        addProvider(typeid(Container), new ValueProvider!Container(this));
    }

    protected void addProvider(TypeInfo info, Provider provider) pure
    out {
        assert(info in providers);
        assert(providers[info].mainProvider);
    }
    body {
        auto providerGroup = info in providers;
        if (providerGroup) {
            providerGroup.mainProvider = provider;
        } else {
            providers[info] = ProviderGroup(provider);
        }
    }

    protected void addProvider(TypeInfo info, string name, Provider provider) pure
    out {
        assert(info in providers);
        assert(name in providers[info].namedProviders);
        assert(providers[info].mainProvider);
    }
    body {
        auto providerGroup = info in providers;
        if (providerGroup) {
            providerGroup.namedProviders[name] = provider;
        } else {
            providers[info] = ProviderGroup(provider, [name: provider]);
        }
    }

    void* resolveInstance(TypeInfo info) {
        auto providerGroup = info in providers;
        assert(providerGroup, "Unable to resolve " ~ info.toString());
        return providerGroup.mainProvider.provide();
    }

    void* resolveInstance(TypeInfo info, string name) {
        auto providerGroup = info in providers;
        assert(providerGroup, "Unable to resolve " ~ info.toString());

        auto provider = name in providerGroup.namedProviders;
        assert(provider, "Unable to resolve name " ~ name ~ " for type " ~ info.toString());

        return provider.provide();
    }

    bool canResolve(TypeInfo info) {
        return cast(bool) (info in providers);
    }

    bool canResolve(TypeInfo info, string name) {
        auto providerGroup = info in providers;
        return providerGroup && name in providerGroup.namedProviders;
    }

    private ProviderGroup[TypeInfo] providers;

    private static struct ProviderGroup {
        Provider mainProvider;
        Provider[string] namedProviders;
    }
}

///
unittest {
    import injected.injection;

    @Injectable!(int, Injected!(int, "a"))
    static class A {
        int x;
        int y;
        this(int x, int y) {
            this.x = x;
            this.y = y;
        }
    }
    static class B : A  {
        string name;
        this(int x, int y, string name) {
            super(x, y);
            this.name = name;
        }
    }
    static struct C {
        string name;
        ushort id;
        static ushort idCounter = 0;
    }
    static C makeC() {
        return C("Foo", C.idCounter++);
    }
    auto container = makeContainer();
    container.value!int(0);
    container.value!int("a", 1);
    container.register!A();
    container.register!(A, B)("b");
    container.factory!string(delegate(C c) {
        return c.name;
    });
    container.factory!(C, makeC)();
    container.factory!(C, makeC)("c", No.asSingleton);

    assert(container.resolve!int() == 0);
    assert(container.resolve!int("a") == 1);
    assert(container.resolve!string() == "Foo");
    auto a = container.resolve!A();
    assert(a.x == 0);
    assert(a.y == 1);
    auto b = cast(B) container.resolve!A("b");
    assert(b);
    assert(b.x == 0);
    assert(b.y == 0);
    assert(b.name == "Foo");
    assert(container.resolve!C().id == 0);
    auto c = container.resolve!C("c");
    assert(c.name == "Foo");
    assert(c.id == 1);
    assert(container.resolve!C("c").id == 2);
}

/**
 * Make a new default container
 */
pure Container makeContainer() {
    return new SimpleContainer();
}

/**
 * A dependency container that uses another container
 * to resolve dependencies it doesn't know about itself.
 */
class DerivedContainer : SimpleContainer {
    private Container _parent;

    this(Container parent) {
        _parent = parent;
    }

    @property Container parent() {
        return _parent;
    }

    override void* resolveInstance(TypeInfo info) {
        if (super.canResolve(info)) {
            return super.resolveInstance(info);
        } else {
            return  _parent.resolveInstance(info);
        }
    }

    override void* resolveInstance(TypeInfo info, string name) {
        if (super.canResolve(info, name)) {
            return super.resolveInstance(info, name);
        } else {
            return _parent.resolveInstance(info, name);
        }
    }

    override bool canResolve(TypeInfo info)  {
        return super.canResolve(info) || _parent.canResolve(info);
    }

    override bool canResolve(TypeInfo info, string name) {
        return super.canResolve(info, name) || _parent.canResolve(info);
    }
}

///
unittest {
    auto base = makeContainer();
    base.value!int(6);
    base.value!string("foo");

    auto derived = base.derivedContainer();
    derived.value!string("bar");

    assert(derived.resolve!string() == "bar");
    assert(derived.resolve!int() == 6);
}

/**
 * Create a derived container from a parent container.
 */
DerivedContainer derivedContainer(Container parent) {
    return new DerivedContainer(parent);
}
