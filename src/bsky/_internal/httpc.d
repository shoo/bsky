/*******************************************************************************
 * HTTP client default implimentation
 */
module bsky._internal.httpc;

import std.json;

/*******************************************************************************
 * Dummy http client for test
 */
interface HttpClientBase
{
	/***************************************************************************
	 * 
	 */
	JSONValue get(string url, string[string] param, string delegate() @safe getBearer) @safe;
	
	/***************************************************************************
	 * 
	 */
	JSONValue post(string url, immutable(ubyte)[] data, string mimeType, string delegate() @safe getBearer) @safe;
	
	/***************************************************************************
	 * 
	 */
	uint getLastStatusCode() const @safe;
	
	/***************************************************************************
	 * 
	 */
	string getLastStatusReason() const @safe;
}

/*******************************************************************************
 * Dummy http client for test
 */
class DummyHttpClient(): HttpClientBase
{
	/***************************************************************************
	 * 
	 */
	struct HttpRequest
	{
		///
		string url;
		///
		string query;
		///
		string mimeType;
		///
		string method;
		///
		immutable(ubyte)[] bodyBinary;
		///
		string toString()() const @safe
		{
			import std.format, std.array;
			auto app = appender!string();
			app.formattedWrite!"url=%s\n"(url);
			app.formattedWrite!"query=%s\n"(query);
			app.formattedWrite!"mimeType=%s\n"(mimeType);
			switch (mimeType)
			{
			case "text/plain":
			case "text/html":
			case "application/x-www-form-urlencoded":
				app.formattedWrite!"body=%s"(cast(string)bodyBinary);
				break;
			case "application/json":
				auto jv = parseJSON(cast(string)bodyBinary);
				app.formattedWrite!"body=%s"(jv.toPrettyString(JSONOptions.doNotEscapeSlashes));
				break;
			default:
				app.formattedWrite!"body=%-(%s%)"(bodyBinary);
			}
			return app.data;
		}
	}
	/***************************************************************************
	 * 
	 */
	struct HttpResult
	{
		///
		HttpRequest request;
		///
		uint code;
		///
		string reason;
		///
		string mimeType;
		///
		JSONValue response;
		///
		string toString()() const @safe
		{
			import std.format, std.array;
			auto app = appender!string();
			app.formattedWrite!"status=%d %s\n"(code, reason);
			app.formattedWrite!"mimeType=%s\n"(mimeType);
			switch (mimeType)
			{
			case "text/plain":
			case "text/html":
			case "application/json":
			case "application/x-www-form-urlencoded":
				app.formattedWrite!"body=%s"(response.toPrettyString(JSONOptions.doNotEscapeSlashes));
				break;
			default:
				import std.base64;
				app.formattedWrite!"bodyBinary=%-(%s%)"(Base64.decode(response.str));
			}
			return app.data;
		}
	}
private:
	HttpResult[]  _results;
	HttpResult    _lastResult;
	size_t        _resultPos;
public:
	/***************************************************************************
	 * 
	 */
	void addResult(HttpResult[] result) @safe
	{
		_results ~= result;
	}
	/// ditto
	void addResult(HttpResult result) @safe
	{
		addResult([result]);
	}
	/// ditto
	void addResult(uint statusCode = 200, string reason = "Success", JSONValue jv = JSONValue.init) @trusted
	{
		if (jv.type == JSONType.array)
		{
			foreach (v; jv.array)
				addResult(statusCode, reason, v);
		}
		else
		{
			addResult(HttpResult(HttpRequest.init, statusCode, reason, "application/json", jv));
		}
	}
	/// ditto
	void addResult(uint statusCode = 200, string reason = "Success", string mimeType, immutable(ubyte)[] dat) @safe
	{
		import std.base64;
		addResult(HttpResult(HttpRequest.init, statusCode, reason, mimeType, JSONValue(Base64.encode(dat))));
	}
	/// ditto
	void addResult(JSONValue jv) @trusted
	{
		if (jv.type == JSONType.array)
		{
			foreach (v; jv.array)
				addResult(v);
			return;
		}
		if (jv.type == JSONType.object && "body" in jv)
		{
			import bsky._internal.json;
			addResult(HttpResult(
				HttpRequest.init,
				jv.getValue("code", uint(200)),
				jv.getValue("reason", "OK"),
				jv.getValue("mimeType", "application/json"),
				jv.getValue("body", JSONValue.init)));
		}
		else
		{
			addResult(200, "OK", jv);
		}
	}
	
	/***************************************************************************
	 * 
	 */
	void clearResult() @safe
	{
		_results = null;
		_lastResult = HttpResult.init;
		_resultPos = 0;
	}
	
	/***************************************************************************
	 * 
	 */
	this() @safe
	{
		_results = null;
		_lastResult = HttpResult.init;
	}
	
	/***************************************************************************
	 * 
	 */
	const(HttpResult)[] results() const @safe
	{
		return _results[0.._resultPos];
	}
	
	/***************************************************************************
	 * 
	 */
	override JSONValue get(string url, string[string] param, string delegate() @safe getBearer) @trusted
	{
		import std.uri, std.string;
		if (_results.length == 0)
			return JSONValue.init;
		
		string[] queries;
		foreach (k, v; param)
			queries ~= encodeComponent(k) ~ "=" ~ encodeComponent(v);
		
		if (getBearer)
			getBearer();
		_results[_resultPos].request.url = url;
		_results[_resultPos].request.query = queries.join("&");
		_results[_resultPos].request.method = "GET";
		_lastResult = _results[_resultPos];
		_resultPos++;
		return _lastResult.response;
	}
	
	/***************************************************************************
	 * 
	 */
	override JSONValue post(string url, immutable(ubyte)[] data, string mimeType,
		string delegate() @safe getBearer) @trusted
	{
		if (_results.length == 0)
			return JSONValue.init;
		if (getBearer)
			getBearer();
		_results[_resultPos].request.url = url;
		_results[_resultPos].request.mimeType = mimeType;
		_results[_resultPos].request.bodyBinary = data;
		_results[_resultPos].request.method = "POST";
		_lastResult = _results[_resultPos];
		_resultPos++;
		return _lastResult.response;
	}
	
	/***************************************************************************
	 * 
	 */
	override uint getLastStatusCode() const @safe
	{
		return _results.length == 0 ? 0 : _results[_resultPos-1].code;
	}
	
	/***************************************************************************
	 * 
	 */
	override string getLastStatusReason() const @safe
	{
		return _results.length == 0 ? "" : _results[_resultPos-1].reason;
	}
}

/*******************************************************************************
 * Curl HTTP Client
 * 
 * Attension:
 *     Instantiation creates a dependency on Curl; note the Curl license.
 */
class CurlHttpClient(): HttpClientBase
{
private:
	import std.net.curl;
	import std.array;
	import std.json;
	import std.uri;
	HTTP _client;
	Appender!(ubyte[]) _contentsBuffer;
	HTTP.StatusLine _lastStatus;
	
	void delegate(string url, string query)                                                         _onGetReq;
	void delegate(string url, string msg, string exmsg)                                             _onGetErr;
	void delegate(string url, uint code, string reason, string[string] headers, string mimeType,
		const(ubyte)[] bodyBinary)                                                                  _onGetRes;
	void delegate(string url, string mimeType, const(ubyte)[] bodyBinary)                           _onPostReq;
	void delegate(string url, string msg, string exmsg)                                             _onPostErr;
	void delegate(string url, uint code, string reason, string[string] headers, string mimeType,
		const(ubyte)[] bodyBinary)                                                                  _onPostRes;
	
	pragma(inline) void onGetReq(string url, string query)
	{
		debug if (_onGetReq)
			_onGetReq(url, query);
	}
	
	pragma(inline) void onGetErr(string url, string msg, string exmsg)
	{
		debug if (_onGetErr)
			_onGetErr(url, msg, exmsg);
	}
	
	pragma(inline) void onGetRes(string url, uint code, string reason, string[string] headers,
		const(ubyte)[] bodyBinary)
	{
		debug if (_onGetRes)
			_onGetRes(url, code, reason, headers,
				"content-type" in headers ? headers["content-type"] : null,
				bodyBinary);
	}
	
	pragma(inline) void onPostReq(string url, string mimeType, const(ubyte)[] bodyBinary)
	{
		debug if (_onPostReq)
			_onPostReq(url, mimeType, bodyBinary);
	}
	
	pragma(inline) void onPostErr(string url, string msg, string exmsg)
	{
		debug if (_onPostErr)
			_onPostErr(url, msg, exmsg);
	}
	
	pragma(inline) void onPostRes(string url, uint code, string reason, string[string] headers,
		const(ubyte)[] bodyBinary)
	{
		debug if (_onPostRes)
			_onPostRes(url, code, reason, headers,
				"content-type" in headers ? headers["content-type"] : null,
				bodyBinary);
	}
	
	import std.logger;
	import std.stdio;
	
	pragma(inline) string bodyToString(string mimeType, const(ubyte)[] bodyBinary)
	{
		import std.string;
		import std.format;
		switch (mimeType.split(";")[0].toLower)
		{
		case "text/plain":
		case "text/html":
		case "application/json":
		case "application/x-www-form-urlencoded":
			return cast(string)bodyBinary.idup;
		default:
			return format!"%-(%02X%)"(bodyBinary);
		}
	}
	
	pragma(inline) JSONValue bodyToJson(string mimeType, const(ubyte)[] bodyBinary)
	{
		import std.string;
		import std.format;
		switch (mimeType.split(";")[0].toLower)
		{
		case "text/plain":
		case "text/html":
		case "application/x-www-form-urlencoded":
			return JSONValue(cast(string)bodyBinary.idup);
			break;
		case "application/json":
			return parseJSON(cast(const char[])bodyBinary.idup);
			break;
		default:
			import std.base64;
			import std.format;
			return JSONValue(Base64.encode(bodyBinary));
		}
	}
	
public:
	/***************************************************************************
	 * 
	 */
	this() @trusted
	{
		_client = HTTP();
		_client.onReceive = (ubyte[] dat){
			_contentsBuffer.put(dat);
			return dat.length;
		};
	}
	/// ditto
	this(Logger logger) @trusted
	{
		this();
		setLogger(logger);
	}
	
	/***************************************************************************
	 * 
	 */
	final void setLogger(Logger logger) @trusted
	{
		auto oldGetReq = _onGetReq;
		auto oldGetErr = _onGetErr;
		auto oldGetRes = _onGetRes;
		auto oldPostReq = _onPostReq;
		auto oldPostErr = _onPostErr;
		auto oldPostRes = _onPostRes;
		
		_onGetReq = (string url, string query)
		{
			import std.string;
			if (oldGetReq)
				oldGetReq(url, query);
			logger.tracef("HTTP GET Request:\nurl=%s\nquery=%s", url, query.chompPrefix("?"));
		};
		_onGetErr = (string url, string msg, string exmsg)
		{
			if (oldGetErr)
				oldGetErr(url, msg, exmsg);
			logger.warningf("HTTP GET Error: %s", msg);
		};
		_onGetRes = (string url, uint code, string reason, string[string] headers, string mimeType,
			const(ubyte)[] bodyBinary)
		{
			if (oldGetRes)
				oldGetRes(url, code, reason, headers, mimeType, bodyBinary);
			logger.infof("HTTP GET: url=%s status=%d %s length=%d", url, code, reason, bodyBinary.length);
			logger.tracef("HTTP GET Response:\nheaders=%s\nbody=%s", headers, bodyToString(mimeType, bodyBinary));
		};
		_onPostReq = (string url, string mimeType, const(ubyte)[] bodyBinary)
		{
			if (oldPostReq)
				oldPostReq(url, mimeType, bodyBinary);
			logger.tracef("HTTP POST Request:\nurl=%s\nparameters=%s", url, bodyToString(mimeType, bodyBinary));
		};
		_onPostErr = (string url, string msg, string exmsg)
		{
			if (oldPostErr)
				oldPostErr(url, msg, exmsg);
			logger.warningf("HTTP POST Error: %s", msg);
		};
		_onPostRes = (string url, uint code, string reason, string[string] headers, string mimeType,
			const(ubyte)[] bodyBinary)
		{
			if (oldPostRes)
				oldPostRes(url, code, reason, headers, mimeType, bodyBinary);
			logger.infof("HTTP POST: url=%s status=%d %s length=%d", url, code, reason, bodyBinary.length);
			logger.tracef("HTTP POST Response:\nheaders=%s\nmimeType=%s\nbody=%s",
				headers, mimeType, bodyToString(mimeType, bodyBinary));
		};
	}
	
	/***************************************************************************
	 * 
	 */
	final void setResponseJsonRecorder(string file) @trusted
	{
		setResponseJsonRecorder(File(file, "w+b"));
	}
	/// ditto
	final void setResponseJsonRecorder(File recorder) @trusted
	{
		import std.algorithm;
		auto oldGetRes = _onGetRes;
		auto oldPostRes = _onPostRes;
		static class Recoder
		{
			File file;
			this(File f) @trusted
			{
				file = f;
				file.seek(0, SEEK_END);
				if (file.tell() == 0)
				{
					file.rawWrite("[]\n");
					file.flush();
					file.seek(-2, SEEK_END);
					file.flush();
				}
				else
				{
					file.seek(-3, SEEK_END);
				}
			}
			~this() @trusted
			{
				file.close();
			}
			void add(JSONValue jv)
			{
				import std.format;
				file.lock(LockType.readWrite);
				scope (exit)
					file.unlock();
				char[1] buf;
				file.rawRead(buf[]);
				auto writer = file.lockingBinaryWriter();
				if (buf[0] != '\n')
				{
					file.seek(-2, SEEK_END);
					writer.put("\n");
				}
				else
				{
					file.seek(-3, SEEK_END);
					writer.put(",\n");
				}
				writer.put(jv.toString(JSONOptions.doNotEscapeSlashes));
				writer.put("\n]\n");
				file.seek(-3, SEEK_END);
			}
		}
		auto rec = new Recoder(recorder);
		
		_onGetRes = (string url, uint code, string reason, string[string] headers, string mimeType,
			const(ubyte)[] bodyBinary)
		{
			import bsky._internal.json;
			if (oldGetRes)
				oldGetRes(url, code, reason, headers, mimeType, bodyBinary);
			JSONValue jv;
			jv.setValue("code", code);
			jv.setValue("reason", reason);
			jv.setValue("mimeType", mimeType);
			jv.setValue("body", bodyToJson(mimeType, bodyBinary));
			rec.add(jv);
		};
		_onPostRes = (string url, uint code, string reason, string[string] headers, string mimeType,
			const(ubyte)[] bodyBinary)
		{
			import bsky._internal.json;
			if (oldPostRes)
				oldPostRes(url, code, reason, headers, mimeType, bodyBinary);
			JSONValue jv;
			jv.setValue("code", code);
			jv.setValue("reason", reason);
			jv.setValue("mimeType", mimeType);
			jv.setValue("body", bodyToJson(mimeType, bodyBinary));
			rec.add(jv);
		};
	}
	
	/***************************************************************************
	 * 
	 */
	override JSONValue get(string url, string[string] param, string delegate() @safe getBearer) @trusted
	{
		string[] queries;
		import std.uri;
		import std.string;
		foreach (k, v; param)
			queries ~= encodeComponent(k) ~ "=" ~ encodeComponent(v);
		_client.clearRequestHeaders();
		_contentsBuffer.shrinkTo(0);
		auto query = queries.length > 0 ? "?" ~ queries.join("&") : null;
		_client.url = url ~ query;
		_client.postData = null;
		_client.method = HTTP.Method.get;
		_client.addRequestHeader("Accept", "application/json");
		if (getBearer)
		{
			if (auto bearer = getBearer())
				_client.addRequestHeader("Authorization", "Bearer " ~ bearer);
		}
		onGetReq(url, query.chompPrefix("?"));
		try _client.perform();
		catch (Exception e)
		{
			onGetErr(url, e.msg, e.toString);
			throw e;
		}
		_lastStatus = _client.statusLine;
		onGetRes(url, _lastStatus.code, _lastStatus.reason, _client.responseHeaders, _contentsBuffer.data);
		return parseJSON(cast(char[])_contentsBuffer.data);
	}
	
	/***************************************************************************
	 * 
	 */
	override JSONValue post(string url, immutable(ubyte)[] data, string mimeType,
		string delegate() @safe getBearer) @trusted
	{
		_client.clearRequestHeaders();
		_contentsBuffer.shrinkTo(0);
		_client.url = url;
		if (data.length == 0)
			_client.postData = null;
		else
			_client.setPostData(data, mimeType);
		_client.method = HTTP.Method.post;
		_client.addRequestHeader("Accept", "application/json");
		if (getBearer)
		{
			if (auto bearer = getBearer())
				_client.addRequestHeader("Authorization", "Bearer " ~ bearer);
		}
		onPostReq(url, mimeType, data);
		try _client.perform();
		catch (Exception e)
		{
			onPostErr(url, e.msg, e.toString);
			throw e;
		}
		_lastStatus = _client.statusLine;
		onPostRes(url, _lastStatus.code, _lastStatus.reason, _client.responseHeaders, _contentsBuffer.data);
		return parseJSON(cast(char[])_contentsBuffer.data);
	}
	
	/***************************************************************************
	 * 
	 */
	override uint getLastStatusCode() const @safe
	{
		return _lastStatus.code;
	}
	
	/***************************************************************************
	 * 
	 */
	override string getLastStatusReason() const @safe
	{
		return _lastStatus.reason;
	}
}

