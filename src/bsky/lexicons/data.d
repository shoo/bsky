module bsky.lexicons.data;

import bsky._internal.json;
import bsky._internal.attr: name, key, value;

/*******************************************************************************
 * Blob
 */
struct Blob
{
	/***************************************************************************
	 * Type
	 */
	@name("$type") @key @value!"blob"
	string type = "blob";
	
	/***************************************************************************
	 * Reference link
	 */
	struct Ref
	{
		/***********************************************************************
		 * String data of link
		 */
		@name("$link") string link;
	}
	/// ditto
	@name("ref") Ref reference;
	
	/***************************************************************************
	 * MIME type of data
	 */
	string mimeType;
	
	/***************************************************************************
	 * Size of data
	 */
	size_t size;
}

@safe unittest
{
	import std.json;
	auto blob = Blob(
		mimeType: "image/jpeg",
		reference: Blob.Ref(link: "bafkreicypyknhwkg4lpxj6yskyttb3nkvhywv32tohpkt6bz4xhgyqybiq"),
		size: 297434);
	import bsky._internal.json;
	auto jv = blob.serializeToJson();
	assert(jv.deserializeFromJson!Blob == blob);
}
