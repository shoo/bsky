/*******************************************************************************
 * AtProto lexicons types of app.bsky.feed.*
 * 
 * See_Also:
 *     https://github.com/bluesky-social/atproto/tree/main/lexicons/app/bsky/feed
 */
module bsky.lexicons.app.bsky.feed;

public import std.datetime: SysTime;
import bsky._internal.attr: name, key, value, ignoreIf;
import bsky._internal.misc: systimeConverter;
public import bsky.lexicons.data: Blob;
public import bsky.lexicons.com.atproto.repo: StrongRef;

/*******************************************************************************
 * app.bsky.feed.post
 */
struct Post
{
	/***************************************************************************
	 * app.bsky.feed.post#replyRef
	 */
	struct ReplyRef
	{
		/***********************************************************************
		 * Root of reply tree
		 */
		StrongRef root;
		/***********************************************************************
		 * Parent of reply tree
		 */
		StrongRef parent;
	}
}

/*******************************************************************************
 * app.bsky.feed.like
 * 
 * See_Also:
 *     https://github.com/bluesky-social/atproto/tree/main/lexicons/app/bsky/feed/like.json
 */
struct Like
{
	/***************************************************************************
	 * 
	 */
	@name("$type") @key @value!"app.bsky.feed.like"
	string type = "app.bsky.feed.like";
	/***************************************************************************
	 * 
	 */
	StrongRef subject;
	/***************************************************************************
	 * 
	 */
	@systimeConverter
	SysTime createdAt;
}

/*******************************************************************************
 * app.bsky.feed.repost
 * 
 * See_Also:
 *     https://github.com/bluesky-social/atproto/tree/main/lexicons/app/bsky/feed/repost.json
 */
struct Repost
{
	/***************************************************************************
	 * 
	 */
	@name("$type") @key @value!"app.bsky.feed.repost"
	string type = "app.bsky.feed.repost";
	/***************************************************************************
	 * 
	 */
	StrongRef subject;
	/***************************************************************************
	 * 
	 */
	@systimeConverter
	SysTime createdAt;
}
