/*******************************************************************************
 * Internal misc functions
 */
module bsky._internal.misc;

package(bsky):

import std.json: JSONValue;
import std.datetime: SysTime;
import std.traits;
import bsky._internal.json: converter;

/*******************************************************************************
 * SysTime converter user data attribute
 */
enum systimeConverter = converter!SysTime(
	jv=>SysTime.fromISOExtString(jv.str),
	v =>JSONValue(v.toISOExtString()));


version (unittest) package(bsky) T readDataSource(T = immutable(ubyte)[])(string fileName) @trusted
{
	import std.file, std.path;
	return cast(T)std.file.read("tests/.ut-data_source".buildPath(fileName));
}

version (unittest) package(bsky) T readDataSource(T: string)(string fileName) @trusted
{
	import std.file, std.path;
	return std.file.readText("tests/.ut-data_source".buildPath(fileName));
}

version (unittest) package(bsky) T readDataSource(T: JSONValue)(string fileName) @trusted
{
	import std.json;
	return readDataSource!string(fileName).parseJSON();
}

version (Have_voile) {
	public import voile.misc: assumePure;
	public import voile.sync: ManagedShared;
}
else:


/*******************************************************************************
 * 
 */
auto ref assumeAttr(alias fn, alias attrs, Args...)(auto ref Args args)
if (isFunction!fn)
{
	alias Func = SetFunctionAttributes!(typeof(&fn), functionLinkage!fn, attrs);
//	if (!__ctfe)
//	{
//		alias dgTy = SetFunctionAttributes!(void function(string), "D", attrs);
//		debug { (cast(dgTy)&disp)(typeof(fn).stringof); }
//	}
	return (cast(Func)&fn)(args);
}

/// ditto
auto ref assumeAttr(alias fn, alias attrs, Args...)(auto ref Args args)
if (__traits(isTemplate, fn) && isCallable!(fn!Args))
{
	alias Func = SetFunctionAttributes!(typeof(&(fn!Args)), functionLinkage!(fn!Args), attrs);
//	if (!__ctfe)
//	{
//		alias dgTy = SetFunctionAttributes!(void function(string), "D", attrs);
//		debug { (cast(dgTy)&disp)(typeof(fn!Args).stringof); }
//	}
	return (cast(Func)&fn!Args)(args);
}

/// ditto
auto assumeAttr(alias attrs, Fn)(Fn t)
	if (isFunctionPointer!Fn || isDelegate!Fn)
{
	return cast(SetFunctionAttributes!(Fn, functionLinkage!Fn, attrs)) t;
}

/*******************************************************************************
 * 
 */
template getFunctionAttributes(T...)
{
	alias fn = T[0];
	static if (T.length == 1 && (isFunctionPointer!(T[0]) || isDelegate!(T[0])))
	{
		enum getFunctionAttributes = functionAttributes!fn;
	}
	else static if (!is(typeof(fn!(T[1..$]))))
	{
		enum getFunctionAttributes = functionAttributes!(fn);
	}
	else
	{
		enum getFunctionAttributes = functionAttributes!(fn!(T[1..$]));
	}
}

/*******************************************************************************
 * 
 */
auto ref assumePure(alias fn, Args...)(auto ref Args args)
{
	return assumeAttr!(fn, getFunctionAttributes!(fn, Args) | FunctionAttribute.pure_, Args)(args);
}

/// ditto
auto assumePure(T)(T t)
if (imported!"std.traits".isFunctionPointer!T || isDelegate!T)
{
	return assumeAttr!(getFunctionAttributes!T | FunctionAttribute.pure_)(t);
}

/*******************************************************************************
 * 
 */
auto ref assumeNogc(alias fn, Args...)(auto ref Args args)
{
	return assumeAttr!(fn, getFunctionAttributes!(fn, Args) | FunctionAttribute.nogc, Args)(args);
}

/// ditto
auto assumeNogc(T)(T t)
	if (isFunctionPointer!T || isDelegate!T)
{
	return assumeAttr!(getFunctionAttributes!T | FunctionAttribute.nogc)(t);
}


/*******************************************************************************
 * 
 */
auto ref assumeNothrow(alias fn, Args...)(auto ref Args args)
{
	return assumeAttr!(fn, getFunctionAttributes!(fn, Args) | FunctionAttribute.nothrow_, Args)(args);
}

/// ditto
auto assumeNothrow(T)(T t)
	if (isFunctionPointer!T || isDelegate!T)
{
	return assumeAttr!(getFunctionAttributes!T | FunctionAttribute.nothrow_)(t);
}



/*******************************************************************************
 * 管理された共有資源
 * 
 * 
 */
class ManagedShared(T): Object.Monitor
{
private:
	import std.exception;
	import core.sync.mutex;
	static struct MonitorProxy
	{
		Object.Monitor link;
	}
	MonitorProxy _proxy;
	Mutex        _mutex;
	size_t       _locked;
	T            _data;
	void _initData(bool initLocked)
	{
		_proxy.link = this;
		this.__monitor = &_proxy;
		_mutex = new Mutex();
		if (initLocked)
			lock();
	}
public:
	
	/***************************************************************************
	 * コンストラクタ
	 * 
	 * sharedのコンストラクタを呼んだ場合の初期状態は共有資源(unlockされた状態)
	 * 非sharedのコンストラクタを呼んだ場合の初期状態は非共有資源(lockされた状態)
	 */
	this()() @trusted
	{
		// これはひどい
		(cast(void delegate(bool) pure)&_initData)(true);
	}
	
	/// ditto
	this()() @trusted shared
	{
		(cast(void delegate(bool) pure)(&(cast()this)._initData))(false);
	}
	
	
	/***************************************************************************
	 * 
	 */
	inout(Mutex) mutex() pure nothrow @nogc inout @property
	{
		return _mutex;
	}
	
	
	/***************************************************************************
	 * 
	 */
	shared(inout(Mutex)) mutex() pure nothrow @nogc shared inout @property
	{
		return _mutex;
	}
	
	
	/***************************************************************************
	 * ロックされたデータを得る
	 * 
	 * この戻り値が破棄されるときにRAIIで自動的にロックが解除される。
	 * また、戻り値はロックされた共有資源へ、非共有資源としてアクセス可能な参照として使用できる。
	 */
	auto locked() @safe @property // @suppress(dscanner.confusing.function_attributes)
	{
		lock();
		static struct LockedData
		{
		private:
			T*              _data;
			void delegate() _unlock;
		public:
			ref inout(T) dataRef() inout @property { return *_data; }
			@disable this(this);
			~this() @trusted
			{
				if (_unlock)
					_unlock();
			}
			alias dataRef this;
		}
		return LockedData(&_data, &unlock);
	}
	/// ditto
	auto locked() @trusted shared inout @property
	{
		return (cast()this).locked();
	}
	
	
	/***************************************************************************
	 * ロックを試行する。
	 * 
	 * Returns:
	 *     すでにロックしているならtrue
	 *     ロックされていなければロックしてtrue
	 *     別のスレッドにロックされていてロックできなければfalse
	 */
	bool tryLock() @safe
	{
		auto tmp = (() @trusted => _mutex.tryLock())();
		// ロックされていなければ _locked を操作することは許されない
		if (tmp)
			_locked++;
		return tmp;
	}
	/// ditto
	bool tryLock() @trusted shared
	{
		return (cast()this).tryLock();
	}
	
	
	/***************************************************************************
	 * ロックする。
	 */
	void lock() @safe
	{
		_mutex.lock();
		_locked++;
	}
	/// ditto
	void lock() @trusted shared
	{
		(cast()this).lock();
	}
	
	
	/***************************************************************************
	 * ロック解除する。
	 */
	void unlock() @safe
	{
		_locked--;
		_mutex.unlock();
	}
	/// ditto
	void unlock() @trusted shared
	{
		(cast()this).unlock();
	}
	
	
	/***************************************************************************
	 * 非共有資源としてアクセスする
	 */
	ref T asUnshared() inout @property
	{
		enforce(_locked != 0);
		return *cast(T*)&_data;
	}
	/// ditto
	ref T asUnshared() shared inout @property
	{
		enforce(_locked != 0);
		return *cast(T*)&_data;
	}
	
	
	/***************************************************************************
	 * 共有資源としてアクセスする
	 */
	ref shared(T) asShared() inout @property
	{
		return *cast(shared(T)*)&_data;
	}
	/// ditto
	ref shared(T) asShared() shared inout @property
	{
		return *cast(shared(T)*)&_data;
	}
}


/*******************************************************************************
 * 
 */
ManagedShared!T managedShared(T)(T dat)
{
	import std.algorithm: move;
	auto s = new ManagedShared!T;
	s.asUnshared = dat.move();
	return s;
}

/// ditto
ManagedShared!T managedShared(T, Args...)(Args args)
{
	auto s = new ManagedShared!T;
	static if (Args.length == 0 && is(typeof(s.asUnshared.__ctor())))
	{
		s.asUnshared.__ctor();
	}
	else static if (is(typeof(s.asUnshared.__ctor(args))))
	{
		s.asUnshared.__ctor(args);
	}
	else static if (is(T == struct) && is(typeof(T(args))))
	{
		s.asUnshared = T(args);
	}
	return s;
}
