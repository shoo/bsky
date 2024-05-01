/*******************************************************************************
 * Post information
 * 
 * License: BSL-1.0
 */
module bsky.post;

import std.sumtype;
import std.range: isInputRange, ElementType;
import bsky._internal;
import bsky.data;

/*******************************************************************************
 * Post information
 */
struct Post
{
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
	struct Author
	{
		import bsky.user: User;
		/***************************************************************************
		 * 
		 */
		string did;
		
		/***************************************************************************
		 * 
		 */
		string handle;
		
		/***************************************************************************
		 * 
		 */
		string displayName;
		
		/***************************************************************************
		 * 
		 */
		string avatar;
		
		/***************************************************************************
		 * 
		 */
		User.Viewer viewer;
		
		/***************************************************************************
		 * 
		 */
		Label[] labels;
	}
	/// ditto
	Author author;
	
	/***************************************************************************
	 * 
	 */
	JSONValue record;
	
	/***************************************************************************
	 * 
	 */
	JSONValue embed;
	
	/***************************************************************************
	 * 
	 */
	size_t replyCount;
	
	/***************************************************************************
	 * 
	 */
	size_t repostCount;
	
	/***************************************************************************
	 * 
	 */
	size_t likeCount;
	
	/***************************************************************************
	 * 
	 */
	@systimeConverter
	SysTime indexedAt;
	
	/***************************************************************************
	 * 
	 */
	struct Viewer
	{
		/***************************************************************************
		 * 
		 */
		string repost;
		/***************************************************************************
		 * 
		 */
		string like;
		/***************************************************************************
		 * 
		 */
		bool replyDisabled;
	}
	/// ditto
	Viewer viewer;
	
	/***************************************************************************
	 * 
	 */
	Label[] labels;
	
	/***************************************************************************
	 * 
	 */
	struct ThreadGate
	{
		/***********************************************************************
		 * 
		 */
		string uri;
		/***********************************************************************
		 * 
		 */
		string cid;
		/***********************************************************************
		 * 
		 */
		JSONValue record;
		/***********************************************************************
		 * 
		 */
		struct List
		{
			/*******************************************************************
			 * 
			 */
			string uri;
			/*******************************************************************
			 * 
			 */
			string cid;
			/*******************************************************************
			 * 
			 */
			string name;
			/*******************************************************************
			 * 
			 */
			string purpose;
			/*******************************************************************
			 * 
			 */
			string avatar;
			/*******************************************************************
			 * 
			 */
			Label[] labels;
			/*******************************************************************
			 * 
			 */
			struct Viewer
			{
				/***************************************************************
				 * 
				 */
				bool muted;
				/***************************************************************
				 * 
				 */
				bool blocked;
			}
			/// ditto
			Viewer viewer;
			/*******************************************************************
			 * 
			 */
			@systimeConverter
			SysTime indexedAt;
		}
		/// ditto
		List[] lists;
	}
	/// ditto
	ThreadGate threadgate;
}

@safe unittest
{
	import std.json;
	auto jv = readDataSource!JSONValue("fe3b5003-a909-496f-a5de-97b1186f7bba.json");
	Post p;
	(() @trusted => p.deserializeFromJson(jv["posts"][0]))();
	assert(p.author.handle == "krzblhls379.vkn.io");
}


/*******************************************************************************
 * Post information
 */
struct Reply
{
	/***************************************************************************
	 * 
	 */
	struct NotFoundPost
	{
		/***********************************************************************
		 * 
		 */
		string uri;
		/***********************************************************************
		 * 
		 */
		@kind(true)
		bool notFound;
	}
	
	/***************************************************************************
	 * 
	 */
	struct BlockedPost
	{
		/***********************************************************************
		 * 
		 */
		string uri;
		/***********************************************************************
		 * 
		 */
		@kind(true)
		bool blocked;
		/***********************************************************************
		 * 
		 */
		Post.Author author;
	}
	
	/***************************************************************************
	 * 
	 */
	SumType!(NotFoundPost, BlockedPost, Post) root;
	
	/***************************************************************************
	 * 
	 */
	SumType!(NotFoundPost, BlockedPost, Post) parent;
	
	/***************************************************************************
	 * 
	 */
	this(this) @trusted {}
}

/*******************************************************************************
 * 
 */
struct Feed
{
	/***************************************************************************
	 * 
	 */
	Post post;
	/***************************************************************************
	 * 
	 */
	Reply reply;
	/***************************************************************************
	 * 
	 */
	struct Reason
	{
		/***********************************************************************
		 * 
		 */
		Post.Author by;
		/***********************************************************************
		 * 
		 */
		@systimeConverter
		SysTime indexedAt;
	}
	/// ditto
	Reason reason;
}


/*******************************************************************************
 * 
 */
struct Message
{
	/***************************************************************************
	 * Uri of post as `at://...`
	 */
	string uri;
	
	/***************************************************************************
	 * Post text
	 */
	string text;
	
	/***************************************************************************
	 * Image data
	 */
	struct Image
	{
		/***********************************************************************
		 * Image uri as `https://...`
		 */
		string uri;
		/***********************************************************************
		 * Thumbnail uri as `https://...`
		 */
		string thumb;
		/***********************************************************************
		 * Alt message of image
		 */
		string alt;
	}
	
	/***************************************************************************
	 * Post images uri as `https://...`
	 */
	Image[] images;
	
	/***************************************************************************
	 * User data
	 */
	struct User
	{
		/***********************************************************************
		 * ID of user
		 */
		string did;
		/***********************************************************************
		 * Handle name
		 */
		string handle;
		/***********************************************************************
		 * Display name
		 */
		string displayName;
	}
	/***************************************************************************
	 * User data of the post author
	 */
	User postBy;
	
	/***************************************************************************
	 * User data of the author who made this repost
	 */
	User repostBy;
	
	/***************************************************************************
	 * User data of the author whom this reply message was sent
	 */
	User replyTo;
	
	/***************************************************************************
	 * Reply target message uri as `at://...`
	 */
	string replyToUri;
	
	/***************************************************************************
	 * Liking count of this post
	 */
	size_t likeCount;
	
	/***************************************************************************
	 * Repost count of this post
	 */
	size_t repostCount;
	
	/***************************************************************************
	 * Time of post created
	 */
	@systimeConverter
	SysTime postTime;
	
	/***************************************************************************
	 * Time of repost created
	 */
	@systimeConverter
	SysTime repostTime;
	
	/***************************************************************************
	 * 
	 */
	bool isReply()
	{
		return replyTo.did.length > 0;
	}
	
	/***************************************************************************
	 * 
	 */
	bool isRepost()
	{
		return repostBy.did.length > 0;
	}
}

/*******************************************************************************
 * 
 */
Message toMessage(in Post post) @safe
{
	import std.json: JSONValue, JSONType;
	Message ret;
	ret.uri = post.uri;
	ret.postBy = Message.User(post.author.did, post.author.handle, post.author.displayName);
	ret.text = post.record.getValue("text", "");
	if (!post.embed.isNull)
	{
		if (auto imagesJv = "images" in post.embed)
		{
			if (imagesJv.type == JSONType.array) foreach (imageJv; (() @trusted => imagesJv.array)())
			{
				Message.Image img;
				if (auto urlJv = "fullsize" in imageJv)
				{
					if (urlJv.type == JSONType.string)
						img.uri = urlJv.str;
				}
				if (auto urlJv = "thumb" in imageJv)
				{
					if (urlJv.type == JSONType.string)
						img.thumb = urlJv.str;
				}
				if (auto altJv = "alt" in imageJv)
				{
					if (altJv.type == JSONType.string)
						img.alt = altJv.str;
				}
				if (img !is Message.Image.init)
					ret.images ~= img;
			}
		}
		// RecodeWithMedia
		if (auto mediaJv = "media" in post.embed)
		{
			if (mediaJv.type == JSONType.object) if (auto imagesJv = "images" in *mediaJv)
			{
				if (imagesJv.type == JSONType.array) foreach (imageJv; (() @trusted => imagesJv.array)())
				{
					Message.Image img;
					if (auto urlJv = "fullsize" in imageJv)
					{
						if (urlJv.type == JSONType.string)
							img.uri = urlJv.str;
					}
					if (auto urlJv = "thumb" in imageJv)
					{
						if (urlJv.type == JSONType.string)
							img.thumb = urlJv.str;
					}
					if (auto altJv = "alt" in imageJv)
					{
						if (altJv.type == JSONType.string)
							img.alt = altJv.str;
					}
					if (img !is Message.Image.init)
						ret.images ~= img;
				}
			}
		}
	}
	ret.likeCount = post.likeCount;
	ret.repostCount = post.repostCount;
	if (auto timJv = "createdAt" in post.record)
	{
		ret.postTime = timJv.type == JSONType.string
			? SysTime.fromISOExtString(timJv.str).toLocalTime()
			: post.indexedAt;
	}
	else
	{
		ret.postTime = post.indexedAt;
	}
	return ret;
}

/// ditto
Message toMessage(Feed feed) @safe
{
	Message ret;
	if (feed.post.uri.length > 0)
		ret = toMessage(feed.post);
	if (feed.reason.by.did.length > 0)
	{
		// Repost
		ret.repostBy = Message.User(feed.reason.by.did, feed.reason.by.handle, feed.reason.by.displayName);
		ret.repostTime = feed.reason.indexedAt;
	}
	if (feed.reply !is Reply.init)
	{
		// Reply
		feed.reply.parent.match!(
			(Post post)
			{
				ret.replyToUri = post.uri;
				ret.replyTo = Message.User(post.author.did, post.author.handle, post.author.displayName);
			},
			(_){}
		);
	}
	return ret;
}

/// ditto
auto toMessages(Range)(Range posts) @safe
if (isInputRange!Range && is(ElementType!Range: Post))
{
	import std.algorithm: map;
	return posts.map!toMessage;
}

/// ditto
auto toMessages(Range)(Range feeds) @safe
if (isInputRange!Range && is(ElementType!Range: Feed))
{
	import std.algorithm: map;
	return feeds.map!toMessage;
}

@safe unittest
{
	import std.json;
	auto jv = readDataSource!JSONValue("fe3b5003-a909-496f-a5de-97b1186f7bba.json");
	Post[] posts;
	(() @trusted => posts.deserializeFromJson(jv["posts"]))();
	auto msg = posts.toMessages();
	assert(msg[0].uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/hyq6lbnl45len");
}

@safe unittest
{
	import std.json;
	auto jv = readDataSource!JSONValue("657d70c5-eb4d-4b33-ab35-86a1589c2e9a.json");
	Feed[] feed;
	(() @trusted => feed.deserializeFromJson(jv[0]["body"]["feed"]))();
	auto msg = feed.toMessages();
	assert(msg[0].uri == "at://did:plc:jm26v6khcj237cfl5e3d4kmx/app.bsky.feed.post/rvhnzoikmc3aa");
}

@safe unittest
{
	import std.json;
	auto jv = readDataSource!JSONValue("49ed9c5d-d355-4f3a-81fb-cab01d1c7e64.json");
	Post[] posts;
	(() @trusted => posts.deserializeFromJson(jv[0]["body"]["posts"]))();
	auto msg = posts.toMessages();
	assert(msg[0].uri == "at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/2a7dtnyusr74f");
	assert(msg[1].uri == "at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/q2dbegoee2gnd");
	assert(msg[2].uri == "at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/i3bao2sbegi5d");
}
