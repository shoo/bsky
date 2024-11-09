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
 * app.bsky.embed.defs.aspectRatio
 * 
 * width:height represents an aspect ratio. It may be approximate, and may not
 * correspond to absolute dimensions in any given unit.
 */
struct AspectRatio
{
	/***************************************************************************
	 * Width
	 * 
	 * minimum = 1
	 */
	int width;
	
	/***************************************************************************
	 * Height
	 * 
	 * minimum = 1
	 */
	int height;
}

/*******************************************************************************
 * app.bsky.embed.images: Embed data of images
 * 
 * A set of images embedded in a Bluesky record (eg, a post).
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
		/***********************************************************************
		 * Aspect ratio
		 */
		@ignoreIf!(img => img.aspectRatio is AspectRatio.init)
		AspectRatio aspectRatio;
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
	this(Blob blob, string alt, AspectRatio aspect = AspectRatio.init) pure nothrow @safe
	{
		this(Image(blob, alt, aspect));
	}
	/// ditto
	this(Blob blob, string alt, int width, int height) pure nothrow @safe
	{
		this(blob, alt, AspectRatio(width, height));
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
	assert("aspectRatio" !in jv["images"][0]);
	auto imgs2 = jv.deserializeFromJson!Images;
	assert(imgs == imgs2);
	
	jv = Images(Blob.init, "test", 100, 40).serializeToJson();
	assert(jv.getValue!string("$type") == "app.bsky.embed.images");
	assert("images" in jv);
	assert(jv["images"].type == JSONType.array);
	assert(jv["images"][0].getValue!string("alt") == "test");
	assert(jv["images"][0]["aspectRatio"]["width"].get!int == 100);
	assert(jv["images"][0]["aspectRatio"]["height"].get!int == 40);
}

/*******************************************************************************
 * app.bsky.embed.external: Embed data of external link
 * 
 * A representation of some externally linked content (eg, a URL and 'card'),
 * embedded in a Bluesky record (eg, a post).
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
 * app.bsky.embed.record: Embed data of record
 * 
 * A representation of a record embedded in a Bluesky record (eg, a post).
 * For example, a quote-post, or sharing a feed generator record.
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
	alias Media = SumType!(Images, Video, External);
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
	this(Record record, Video video) pure nothrow @nogc @safe
	{
		this(record, Media(video));
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
	/// ditto
	this(StrongRef record, Video video) pure nothrow @nogc @safe
	{
		this(Record(record), video);
	}
}
/// ditto
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


/*******************************************************************************
 * app.bsky.embed.video: Embed data of video
 * 
 * A video embedded in a Bluesky record (eg, a post).
 */
struct Video
{
	/***************************************************************************
	 * Type
	 */
	@name("$type") @key @value!"app.bsky.embed.video"
	string type = "app.bsky.embed.video";
	
	/***************************************************************************
	 * Video data
	 */
	Blob video;
	
	/***************************************************************************
	 * Caption data
	 */
	struct Caption
	{
		/***********************************************************************
		 * Language
		 */
		string lang;
		/***********************************************************************
		 * File
		 * 
		 * Accept: text/vtt
		 */
		Blob file;
	}
	/// ditto
	@ignoreIf!(video => video.captions.length == 0)
	Caption[] captions;
	
	/***************************************************************************
	 * Alt string
	 * 
	 * Alt text description of the video, for accessibility.
	 */
	@ignoreIf!(video => video.alt.length == 0)
	string alt;
	
	/***************************************************************************
	 * Aspect ratio
	 */
	@ignoreIf!(video => video.aspectRatio is AspectRatio.init)
	AspectRatio aspectRatio;
}

@safe unittest
{
	import std.json;
	import bsky._internal.json;
	auto video = Video();
	auto jv = video.serializeToJson();
	assert(jv.getValue!string("$type") == "app.bsky.embed.video");
	assert("video" in jv);
	assert(jv["video"].type == JSONType.object);
	assert(jv["video"]["ref"]["$link"].type == JSONType.string);
	assert("alt" !in jv["video"]);
	assert("aspectRatio" !in jv["video"]);
	assert("captions" !in jv["video"]);
	auto video2 = jv.deserializeFromJson!Video;
	assert(video == video2);
	
	jv = Video(
		video: Blob.init,
		captions: [Video.Caption("ja", Blob.init)],
		alt: "test",
		aspectRatio: AspectRatio(100, 40)).serializeToJson();
	assert(jv.getValue!string("$type") == "app.bsky.embed.video");
	assert("video" in jv);
	assert(jv["video"].type == JSONType.object);
	assert(jv["alt"].str == "test");
	assert(jv["captions"][0]["lang"].str == "ja");
	assert(jv["aspectRatio"]["width"].get!int == 100);
	assert(jv["aspectRatio"]["height"].get!int == 40);
}


alias Embed = SumType!(Images, External, Record, RecordWithMedia, Video);
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
