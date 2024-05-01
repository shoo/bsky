/*******************************************************************************
 * AtProto lexicons record types of com.atproto.repo.*
 * 
 * See_Also:
 *     https://github.com/bluesky-social/atproto/tree/main/lexicons/com/atproto/repo
 */
module bsky.lexicons.com.atproto.repo;

/*******************************************************************************
 * A URI with a content-hash fingerprint.
 */
struct StrongRef
{
	/***************************************************************************
	 * 
	 */
	string uri;
	/***************************************************************************
	 * 
	 */
	string cid;
}
