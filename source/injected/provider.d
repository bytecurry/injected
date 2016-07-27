module injected.provider;

import std.traits : ReturnType, Parameters, isCallable;

import injected.injection;
import injected.resolver : isRefType, Resolver;

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

    this(T val) pure {
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

unittest {
    Provider provider = new ValueProvider!int(10);
    assert(provider.providedType == typeid(int));
    assert(*(cast(int*) provider.provide()) == 10);

}

unittest {
    class C {}
    auto c = new C();
    auto provider = new ValueProvider!C(c);
    assert(provider.providedType == typeid(C));
    assert((cast(C) provider.provide()) is c);
}

/**
 * A Provider that uses another provider to create an instance
 * the first time `provide` is called. Future calls to `provide`
 * will return this same instance.
 */
class SingletonProvider : Provider {
    private Provider _base;
    private void* _instance;

    this(Provider baseProvider) pure nothrow {
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

unittest {
    class BaseProvider : Provider {
        private int counter = 0;

        void* provide() {
            return new int(counter++);
        }

        @property TypeInfo providedType() const {
            return typeid(int);
        }
    }

    auto provider = new SingletonProvider(new BaseProvider);
    assert(provider.providedType == typeid(int));
    int* first = cast(int*) provider.provide();
    assert(*first == 0);
    assert(provider.provide() is first);
    *first = 10;
    assert(*(cast(int*) provider.provide()) == 10);
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

    private alias Injectables = getInjectables!(T);

    static if (Injectables.length > 0) {
        private alias Injections = Injectables[0].Injections;
    } else {
        private alias Injections = Parameters!(__traits(getMember, T, "__ctor"));
    }

    this(Resolver resolver) pure {
        _resolver = resolver;
    }

    void* provide() {
        return cast(void*) new T(injectionSeq!(Injections)(_resolver).expand);
    }

    @property TypeInfo_Class providedType() const {
        return typeid(T);
    }
}

unittest {
    import injected.container;

    static class A {}
    static class B {}
    static class Test {
        this(A a, B b, int c) {
            this.a = a;
            this.b = b;
            this.c = c;
        }
        this(A a, B b) {
            this.a = a;
            this.b = b;
            this.c = -1;
        }
        A a;
        B b;
        int c;
    }

    auto container = makeContainer();
    auto a = new A();
    auto b = new B();
    container.value!A(a);
    container.value!B(b);
    container.value!int(10);

    auto provider = new ClassProvider!Test(container);
    assert(provider.providedType == typeid(Test));

    auto test = cast(Test) provider.provide();
    assert(test);
    assert(test.a is a);
    assert(test.b is b);
    assert(test.c == 10);
}

unittest {
    import injected.injection;
    import injected.container;

    @Injectable!(Injected!(int,"a"), Injected!(int, "b"), float)
    static class Test {
        this() { }
        this(int a, int b, float c) {
            this.a = a;
            this.b = b;
            this.c = c;
        }
        int a;
        int b;
        float c;
    }

    auto container = makeContainer();
    container.value!int("a", 5);
    container.value!int("b", 10);
    container.value!float(3.14);

    auto provider = new ClassProvider!Test(container);
    assert(provider.providedType == typeid(Test));

    auto test = cast(Test) provider.provide();
    assert(test);
    import std.stdio;
    assert(test.a == 5);
    assert(test.b == 10);
    assert(test.c == 3.14f);
}

/**
 * A provider that uses a factory function (or other callable) to
 * get the value.
 *
 * Arguments to the function are resolved using a `Resolver` (typically a `Container`).
 * If an `Injectable` annotation is on the definition of the function, then the template
 * arguments to the `Injectable` determine how the injected arguments should be resolved.
 * Otherwise, the argument types for the function are used.
 *
 * The function can either be passed as an alias function argument or as a parameter
 * to the constructor, depending on the needs of the user.
 */
class FactoryProvider(alias F) : Provider if (isCallable!F) {
    private Resolver _resolver;

    private alias Injectables = getInjectables!(F);
    static if (Injectables.length > 0) {
        private alias Injections = Injectables[0].Injections;
    } else {
        private alias Injections = Parameters!F;
    }

    /**
     * Parameters: `resolver` is used to resolve the arguments to the factory function
     * which could be either be specified using an `Injectable` annotation, or inferred
     * from the parameter list of the function.
     */
    this(Resolver resolver) pure {
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

unittest {
    import injected.container;
    static class A {}
    auto a = new A();

    static struct Result {
        A a;
        int b;
        string c;
        int d;
    }

    auto container = makeContainer();
    container.value!int(6);
    container.value!string("foo");
    container.value!A(a);
    container.value!int("d", 1);

    Result test1(A a, int b, string c) {
        return Result(a, b, c);
    }

    @Injectable!(A, Injected!int, string, Injected!(int, "d"))
    Result test2(A a, int b, string c, int d) {
        return Result(a, b, c, d);
    }

    Provider provider = new FactoryProvider!test1(container);
    assert(provider.providedType == typeid(Result));
    auto result = cast(Result*) provider.provide();
    assert(result.a is a);
    assert(result.b == 6);
    assert(result.c == "foo");
    assert(result.d == int.init);

    provider = new FactoryProvider!test2(container);
    assert(provider.providedType == typeid(Result));
    result = cast(Result*) provider.provide();
    assert(result.a is a);
    assert(result.b == 6);
    assert(result.c == "foo");
    assert(result.d == 1);
}

/// ditto
class FactoryProvider(F) : Provider if (is(F == function) || is(F == delegate)) {
    private Resolver _resolver;
    private F _func;

    private alias Injections = Parameters!F;

    /**
     * Parameters: `resolver` is used to resolve arguments, `func` is the factory function to use.
     */
    this(Resolver resolver, F func) pure {
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

unittest {
    import injected.container;

    class A {}
    auto a = new A();
    class B {}
    auto b = new B();
    class C {}
    auto c = new C();

    static struct Result {
        A a;
        B b;
        C c;
    }

    auto container = makeContainer();
    container.value(a);
    container.value(b);
    container.value(c);

    auto dg = delegate(A a, B b, C c) {
        return Result(a, b, c);
    };

    auto provider = new FactoryProvider!(typeof(dg))(container, dg);
    assert(provider.providedType == typeid(Result));
    auto result = cast(Result*) provider.provide();

    assert(result.a is a);
    assert(result.b is b);
    assert(result.c is c);
}

/**
 * Convert any type to a `void*`.
 * If it is a reference type, caast it,
 * otherwise allocate heap memory for it and return a pointer.
 */
private void* toVoidPtr(T)(T value) pure {
    static if (isRefType!T) {
        return cast(void*) value;
    } else {
        import std.array : uninitializedArray;
        // for structs we need to allocate the memory before initializing
        // see https://issues.dlang.org/show_bug.cgi?id=12918
        auto result = cast(T*) uninitializedArray!(void[])(T.sizeof).ptr;
        *result = value;
        return cast(void*) result;
    }
}


unittest {
    auto ptr = toVoidPtr!int(15);
    assert(is(typeof(ptr) == void*));
    assert(*(cast(int*) ptr) == 15);

    static class C {}
    auto c = new C;
    ptr = toVoidPtr(c);
    assert((cast(C) ptr) is c);
}
