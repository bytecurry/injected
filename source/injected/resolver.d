module injected.resolver;

import std.traits : isPointer;

/**
 * Is the type a reference type (that is passed by pointer).
 * That is, is it a class, interface, or pointer type.
 */
template isRefType(T) {
    enum isRefType = is(T == class) || is(T == interface) || isPointer!T;
}

private T fromVoidPtr(T)(void* data) {
    static if (isRefType!T) {
        return cast(T) data;
    } else {
        return *(cast(T*) data);
    }
}

/**
 * Interface for object that can resolve instances of a type, possibly with a name.
 */
interface Resolver {

    /**
     * Resolve an instance of the type of TypeInfo.
     *
     * A name can be used to disambiguate between multiple providers
     *
     * If the type is a pointer, interface, or class it should
     * return the object itself, otherwise it should return a pointer
     * to the data.
     */
    void* resolveInstance(TypeInfo info);

    /// ditto
    void* resolveInstance(TypeInfo info, string name);

    /**
     * Resolve an instance of type T. If name is provided
     * use that to disambiguate between multiple providers.
     */
    final T resolve(T)() {
        return fromVoidPtr!T(resolveInstance(typeid(T)));
    }

    /// ditto
    final T resolve(T)(string name) {
        return fromVoidPtr!T(resolveInstance(typeid(T), name));
    }

    bool canResolve(TypeInfo type);
    bool canResolve(TypeInfo type,  string name);
}
