/*******************************************************************************
 * Common data
 * 
 * License: BSL-1.0
 */
module bsky.data;

import bsky._internal;

/*******************************************************************************
 * 
 */
struct Label
{
	/***************************************************************************
	 * 
	 */
	long ver;
	/***************************************************************************
	 * 
	 */
	string src;
	/***************************************************************************
	 * 
	 */
	string uri;
	/***************************************************************************
	 * 
	 */
	string cid;
	/***************************************************************************
	 * 
	 */
	string val;
	/***************************************************************************
	 * 
	 */
	bool neg;
	/***************************************************************************
	 * 
	 */
	@systimeConverter
	SysTime cts;
	/***************************************************************************
	 * 
	 */
	@systimeConverter
	SysTime exp;
	/***************************************************************************
	 * 
	 */
	string sig;
}


/*******************************************************************************
 * 
 */
struct AtProtoURI
{
	import std.exception;
	/***************************************************************************
	 * AUTHORITY (handle or did)
	 */
	string authority;
	/***************************************************************************
	 * COLLECTION (nsid)
	 */
	string collection;
	/***************************************************************************
	 * RKEY (record key)
	 */
	string rkey;
	
	/***************************************************************************
	 * 
	 */
	this(string uri) @safe
	{
		import std.string;
		enforce(uri.startsWith("at://"));
		auto splitted = split(uri[5..$], '/');
		enforce(splitted.length >= 1);
		authority = splitted[0];
		if (splitted.length > 1)
			collection = splitted[1];
		if (splitted.length > 2)
			rkey = splitted[2];
	}
	
	/***************************************************************************
	 * 
	 */
	bool hasDid() const pure nothrow @nogc @safe
	{
		import std.string;
		return authority.startsWith("did:");
	}
	
	/***************************************************************************
	 * 
	 */
	bool hasHandle() const pure nothrow @nogc @safe
	{
		import std.string;
		return !authority.startsWith("did:");
	}
	
	/***************************************************************************
	 * 
	 */
	bool hasCollection() const pure nothrow @nogc @safe
	{
		return collection.length != 0;
	}
	
	/***************************************************************************
	 * 
	 */
	bool hasRecordKey() const pure nothrow @nogc @safe
	{
		return rkey.length != 0;
	}
	
	/***************************************************************************
	 * 
	 */
	string toString() const pure nothrow @safe
	{
		return "at://" ~ authority ~ (collection.length > 0
			? "/" ~ collection ~ (rkey.length > 0 ? "/" ~ rkey : null)
			: null);
	}
	
}

@safe unittest
{
	auto uri1 = AtProtoURI("at://did:plc:2qfqobqz6dzrfa3jv74i6k6m/app.bsky.feed.post/5ni6rkonpzlx2");
	assert(uri1.hasDid);
	assert(!uri1.hasHandle);
	assert(uri1.hasCollection);
	assert(uri1.hasRecordKey);
	assert(uri1.toString() == "at://did:plc:2qfqobqz6dzrfa3jv74i6k6m/app.bsky.feed.post/5ni6rkonpzlx2");
	auto uri2 = AtProtoURI("at://krzblhls379.vkn.io/app.bsky.feed.post");
	assert(!uri2.hasDid);
	assert(uri2.hasHandle);
	assert(uri2.hasCollection);
	assert(!uri2.hasRecordKey);
	assert(uri2.toString() == "at://krzblhls379.vkn.io/app.bsky.feed.post");
	auto uri3 = AtProtoURI("at://krzblhls379.vkn.io");
	assert(!uri3.hasDid);
	assert(uri3.hasHandle);
	assert(!uri3.hasCollection);
	assert(!uri3.hasRecordKey);
	assert(uri3.toString() == "at://krzblhls379.vkn.io");
}

/*******************************************************************************
 * 
 */
class BlueskyClientException: Exception
{
private:
	import std.exception;
public:
	/***************************************************************************
	 * Status code
	 */
	uint   status;
	/***************************************************************************
	 * Message
	 */
	string reason;
	/***************************************************************************
	 * Response error
	 */
	string resError;
	/***************************************************************************
	 * Response message
	 */
	string resMessage;
	
	/***************************************************************************
	 * Constructor
	 */
	this(uint status, string reason, string resErr, string resMsg, string msg,
		string file = __FILE__, size_t line = __LINE__, Throwable next = null) @nogc @safe pure nothrow
	{
		this.status = status;
		this.reason = reason;
		this.resError = resErr;
		this.resMessage = resMsg;
		super(msg, file, line, next);
	}
	
	mixin basicExceptionCtors!();
}
