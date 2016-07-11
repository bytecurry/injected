module injected.container;

import injected.resolver;
import injected.provider;

enum RegisterOptions {
    None = 0,
    Transient = None,
    Singleton = 1
}

interface Container : Resolver {
    protected void registerType(TypeInfo type, Provider provider);
    protected void registerType(TypeInfo type, string name, Provider provider);

    final void value(T)(string name, T value) {
        registerType(typeid(T), name, new ValueProvider!T(value));
    }

    final void value(T)(T value) {
        registerType(typeid(T), new ValueProvider!T(value));
    }


    final void register(T)(Provider provider, string name = null, RegisterOptions options = RegisterOptions.None) {
        if (options & RegisterOptions.Singleton) {
            provider = new SingletonProvider(provider);
        }
        registerType(typeid(T), provider, name);
    }

    final void register(I, C: I)(string name = null, RegisterOptions options = RegisterOptions.Singleton)
    if (is(C == class)) {
        register!I(new ClassProvider!C(this), name, options);
    }

    final void register(C)(string name = null, RegisterOptions options = RegisterOptions.Singleton)
    if (is(C == class)) {
        register!C(new ClassProvider!C(this), name, options);
    }

    final void factory(T, alias F)(string name = null, RegisterOptions options = RegisterOptions.Singleton) if (isCallable!F && is(ReturnType!F: T)) {
        register!T(new FactoryProvider!F(this), name, options);
    }

    final void factory(T, F)(F func, string name = null, RegisterOptions options = RegisterOptions.Singleton) if ((is(F == delegate) || is(F == function)) && is(ReturnType!F: T)) {
        register!T(new FactoryProvider!F(this, func), name, options);
    }

}


class SimpleContainer : Container {

    pure this() {
        registerType(typeid(Container), new ValueProvider!Container(this));
    }

    pure protected void registerType(TypeInfo info, Provider provider)
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

    pure protected void registerType(TypeInfo info, string name, Provider provider)
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

DerivedContainer derivedContainer(Container parent) {
    return new DerivedContainer(parent);
}
