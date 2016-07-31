module injected.resolver;

/**
 * Interface for object that can resolve instances of a type, possibly with a name.
 */
interface Resolver {

    /**
     * Resolve an instance of the type of TypeInfo, and execute a delegate with
     * a pointer to that instance (as a `void*`).
     *
     * A name can be used to disambiguate between multiple providers
     */
    protected void withResolvedPtr(TypeInfo info, void delegate(void*) dg);
    /// ditto
    protected void withResolvedPtr(TypeInfo info, string name, void delegate(void*) dg);

    /**
     * Resolve an instance of type T. If name is provided
     * use that to disambiguate between multiple providers.
     */
    final T resolve(T)() {
        assert(canResolve(typeid(T)));
        T result;
        withResolvedPtr(typeid(T), delegate(ptr) {
                result = *(cast(T*) ptr);
            });
        return result;
    }

    /// ditto
    final T resolve(T)(string name) {
        assert(canResolve(typeid(T)));
        T result;
        withResolvedPtr(typeid(T), name, delegate(ptr) {
                result = *(cast(T*) ptr);
            });
        return result;
    }

    /**
     * Check if the resolver can resolve a type (possibly with a name).
     */
    bool canResolve(TypeInfo type);
    /// ditto
    bool canResolve(TypeInfo type,  string name);
}
