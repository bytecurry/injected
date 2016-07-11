module injected.provider;

import std.traits : getUDAs, ReturnType, Parameters, isCallable;

import injected.injection;
import injected.resolver : isRefType;

/**
 * Interface for a provider for dependency injection.
 * A provider knows about the type it produces, and
 * can produce a value.
 */
interface Provider {
    /**
     * Produce the value. It is returned as a `void*`
     * so that arbitrary values (not just class objects) can be
     * produced.
     */
    void* provide();

    /**
     * Return a `TypeInfo` describing the type provided.
     */
    @property TypeInfo providedType() const;
}

/**
 * A `Provider` that provides a value. The value is
 * provided at construction type and the same value
 * is returned each time provide is called.
 */
class ValueProvider(T) : Provider {
    T value;

    this(T val) {
        value = val;
    }

    void* provide() {
        static if(isRefType!T) {
            return cast(void*) value;
        } else {
            return &value;
        }
    }

    @property TypeInfo providedType() const {
        return typeid(T);
    }
}

/**
 * A Provider that uses another provider to create an instance
 * the first time `provide` is called. Future calls to `provide`
 * will return this same instance.
 */
class SingletonProvider : Provider {
    private Provider _base;
    private void* _instance;

    this(Provider baseProvider) {
        _base = baseProvider;
    }

    void* provide() {
        synchronized (this) {
            if (_instance is null) {
                _instance = _base.provide();
            }
        }
        return _instance;
    }

    @property TypeInfo providedType() const {
        return _base.providedType();
    }
}

/**
 * A Provider that instantiates instances of a class.
 *
 * Arguments to the constructor are resolved using a `Resolver` (typically a `Container`).
 * If an `Injectable` annotation is on the class, then the template arguments to the `Injectable`
 * determine how the injected arguments should be resolved. Otherwise, the argument types for the
 * first constructor are used.
 */
class ClassProvider(T) : Provider if (is(T == class)) {
    private Resolver _resolver;

    private alias Injectables = getUDAs!(T, Injectable);

    static if (Injectables.length > 0) {
        private alias Injections = Injectables[0].Injections;
    } else {
        private alias Injections = Parameters!(__traits(getMember, T, "__ctor"));
    }

    this(Resolver resolver) {
        _resolver = resolver;
    }

    void* provide() {
        return new T(injectionSeq!(Injections)(_resolver).expand);
    }

    @property TypeInfo_Class providedType() const {
        return typeid(T);
    }
}

class FactoryProvider(alias F) : Provider if (isCallable!F) {
    private Resolver _resolver;

    private alias Injectables = getUDAs!(F, Injectable);
    static if (Injectables.length > 0) {
        private alias Injections = Injectables[0].Injections;
    } else {
        private alias Injections = Parameters!F;
    }

    this(Resolver resolver) {
        _resolver = resolver;
    }

    void* provide() {
        auto value = F(injectionSeq!(Injections)(_resolver).expand);
        return toVoidPtr(value);
    }

    @property TypeInfo providedType() const {
        return typeid(ReturnType!F);
    }
}

class FactoryProvider(F) : Provider if (is(F == function) || is(F == delegate)) {
    private Resolver _resolver;
    private F _func;

    private alias Injections = Parameters!F;

    this(Resolver resolver, F func) {
        _resolver = resolver;
        _func = func;
    }

    void* provide() {
        auto value = _func(injectionSeq!(Injections)(_resolver).expand);
        return toVoidPtr(value);
    }

    @property TypeInfo providedType() const {
        return typeid(ReturnType!F);
    }
}

private void* toVoidPtr(T)(T value) {
    static if (isRefType!T) {
        return cast(void*) value;
    } else {
        // if it isn't a reference type allocate memory for it.
        return cast(void*) new T(value);
    }
}
