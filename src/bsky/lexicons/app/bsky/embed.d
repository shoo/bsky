/*******************************************************************************
 * AtProto lexicons record types of app.bsky.embed.*
 * 
 * See_Also:
 *     https://github.com/bluesky-social/atproto/tree/main/lexicons/app/bsky/embed
 */
module bsky.lexicons.app.bsky.embed;

import bsky._internal.attr: name, key, value, ignoreIf;
public import bsky.lexicons.data: Blob;
public import bsky.lexicons.com.atproto.repo: StrongRef;

import std.sumtype;



/*******************************************************************************
 * Embed data of images
 */
struct Images
{
	/***************************************************************************
	 * Type
	 */
	@name("$type") @key @value!"app.bsky.embed.images"
	string type = "app.bsky.embed.images";
	
	/***************************************************************************
	 * Images data
	 */
	struct Image
	{
		/***********************************************************************
		 * Blob of image
		 */
		Blob image;
		/***********************************************************************
		 * Alt text
		 */
		string alt;
	}
	/// ditto
	Image[] images;
	
	/***************************************************************************
	 * Constructor
	 */
	this(Image[] images) pure nothrow @nogc @safe
	{
		this.images = images;
	}
	/// ditto
	this(Image image) pure nothrow @safe
	{
		this.images = [image];
	}
	/// ditto
	this(Blob blob, string alt) pure nothrow @safe
	{
		this.images = [Image(blob, alt)];
	}
}

@safe unittest
{
	import std.json;
	import bsky._internal.json;
	auto imgs = Images(
		image: Images.Image(Blob.init, "test"));
	auto jv = imgs.serializeToJson();
	assert(jv.getValue!string("$type") == "app.bsky.embed.images");
	assert("images" in jv);
	assert(jv["images"].type == JSONType.array);
	assert(jv["images"][0].getValue!string("alt") == "test");
	auto imgs2 = jv.deserializeFromJson!Images;
	assert(imgs == imgs2);
}

/*******************************************************************************
 * Embed data of external link
 */
struct External
{
	/***************************************************************************
	 * Type
	 */
	@name("$type") @key @value!"app.bsky.embed.external"
	string type = "app.bsky.embed.external";
	
	/***************************************************************************
	 * External data
	 */
	struct External
	{
		/***********************************************************************
		 * URL of external link
		 */
		string uri;
		/***********************************************************************
		 * Title of external link
		 */
		string title;
		/***********************************************************************
		 * Descriptions
		 */
		string description;
		/***********************************************************************
		 * Thumbnail of external link
		 */
		@ignoreIf!(dat => dat.thumb is Blob.init)
		Blob thumb;
	}
	/// ditto
	External external;
	
	/***************************************************************************
	 * Constructor
	 */
	this(External external) pure nothrow @nogc @safe
	{
		this.external = external;
	}
}

@safe unittest
{
	import std.json;
	import bsky._internal.json;
	auto ext = External(
		external: External.External("https://dlang.org"));
	auto jv = ext.serializeToJson();
	assert(jv.getValue!string("$type") == "app.bsky.embed.external");
	assert("external" in jv);
	assert(jv["external"].type == JSONType.object);
	assert(jv["external"].getValue!string("uri") == "https://dlang.org");
	assert("thumb" !in jv["external"]);
	auto ext2 = jv.deserializeFromJson!External;
	assert(ext == ext2);
}

/*******************************************************************************
 * Embed data of record
 */
struct Record
{
	/***************************************************************************
	 * Type
	 */
	@name("$type") @key @value!"app.bsky.embed.record"
	string type = "app.bsky.embed.record";
	
	/***************************************************************************
	 * Record data
	 */
	alias Record = StrongRef;
	/// ditto
	Record record;
	
	/***************************************************************************
	 * Constructor
	 */
	this(Record record) pure nothrow @nogc @safe
	{
		this.record = record;
	}
	
	/// ditto
	this(string uri, string cid) pure nothrow @nogc @safe
	{
		this.record = Record(uri, cid);
	}
}

@safe unittest
{
	import std.json;
	import bsky._internal.json;
	auto rec = Record(
		record: StrongRef("at://test.bsly.social/app.bsky.feed.post/3kpadeirzya27", "abcde"));
	auto jv = rec.serializeToJson();
	assert(jv.getValue!string("$type") == "app.bsky.embed.record");
	assert("record" in jv);
	assert(jv["record"].type == JSONType.object);
	assert(jv["record"].getValue!string("uri") == "at://test.bsly.social/app.bsky.feed.post/3kpadeirzya27");
	assert(jv["record"].getValue!string("cid") == "abcde");
	auto rec2 = jv.deserializeFromJson!Record;
	assert(rec == rec2);
}


/*******************************************************************************
 * Embed data of external link
 */
struct RecordWithMedia
{
	/***************************************************************************
	 * Type
	 */
	@name("$type") @key @value!"app.bsky.embed.recordWithMedia"
	string type = "app.bsky.embed.recordWithMedia";
	
	/***************************************************************************
	 * Record data
	 */
	Record record;
	
	/***************************************************************************
	 * Image/External data
	 */
	alias Media = SumType!(Images, External);
	/// ditto
	Media media;
	
	/***************************************************************************
	 * Constructor
	 */
	this(Record record, Media media) pure nothrow @nogc @safe
	{
		this.record = record;
		this.media = media;
	}
	/// ditto
	this(Record record, External external) pure nothrow @nogc @safe
	{
		this(record, Media(external));
	}
	/// ditto
	this(Record record, Images images) pure nothrow @nogc @safe
	{
		this(record, Media(images));
	}
	/// ditto
	this(Record record, Images.Image image) pure nothrow @safe
	{
		this(record, Images(image));
	}
	/// ditto
	this(StrongRef record, Media media) pure nothrow @nogc @safe
	{
		this(Record(record), media);
	}
	/// ditto
	this(StrongRef record, External external) pure nothrow @nogc @safe
	{
		this(Record(record), external);
	}
	/// ditto
	this(StrongRef record, Images.Image image) pure nothrow @safe
	{
		this(Record(record), image);
	}
	/// ditto
	this(StrongRef record, Images images) pure nothrow @nogc @safe
	{
		this(Record(record), images);
	}
}
/*******************************************************************************
 * Embed data of external link
 */
@safe unittest
{
	import std.json;
	import bsky._internal.json;
	auto rwm = RecordWithMedia(
		record: Record("at://test.bsly.social/app.bsky.feed.post/3kpadeirzya27", "abcde"),
		image: Images.Image(Blob.init, "test"));
	auto jv = rwm.serializeToJson();
	assert(jv.getValue!string("$type") == "app.bsky.embed.recordWithMedia");
	assert("record" in jv);
	assert("record" in jv["record"]);
	assert("media" in jv);
	assert(jv["record"]["record"].type == JSONType.object);
	assert(jv["record"]["record"].getValue!string("uri") == "at://test.bsly.social/app.bsky.feed.post/3kpadeirzya27");
	assert(jv["record"]["record"].getValue!string("cid") == "abcde");
	assert(jv["media"].getValue!string("$type") == "app.bsky.embed.images");
	auto rwm2 = jv.deserializeFromJson!RecordWithMedia;
	assert(rwm == rwm2);
}

alias Embed = SumType!(Images, External, Record, RecordWithMedia);
@safe unittest
{
	import std.json;
	import bsky._internal.json;
	auto embed = Embed(External(
		external: External.External("https://dlang.org")));
	auto jv = embed.serializeToJson();
	assert(jv.getValue!string("$type") == "app.bsky.embed.external");
	assert("external" in jv);
	assert(jv["external"].type == JSONType.object);
	assert(jv["external"].getValue!string("uri") == "https://dlang.org");
	auto embed2 = jv.deserializeFromJson!Embed;
	assert(embed == embed2);
}
