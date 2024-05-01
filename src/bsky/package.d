/***************************************************************
 * Client library to access Bluesky
 * 
 * For more detailed usage instructions, please refer to the documentation for each module.
 * - $(LINK2 _bsky--_bsky.client.html, _bsky.client) : Client of bluesky.
 * - $(LINK2 _bsky--_bsky.auth.html, _bsky.auth)     : Authenticate management.
 * 
 * Authors: SHOO
 * License: BSL-1.0
 * Copyright: 2024 SHOO
 * Examples:
 * -------------------------------------------------------------
 * import bsky;
 * import std.stdio, std.process;
 * 
 * auto client = new Bluesky;
 * client.login(environment.get("BSKYUT_LOGINID"), environment.get("BSKYUT_LOGINPASS"));
 * scope (exit)
 *     client.logout();
 * writefln("Hello! My name is %s.", client.profile.displayName);
 * -------------------------------------------------------------
 */
module bsky;

///
public import bsky.client;
/// ditto
public import bsky.user;
/// ditto
public import bsky.post;
/// ditto
public import bsky.data;
/// ditto
public import bsky.auth;
