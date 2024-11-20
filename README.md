[![GitHub tag](https://img.shields.io/github/tag/shoo/bsky.svg?maxAge=86400)](#)
[![CI Status](https://github.com/shoo/bsky/actions/workflows/main.yml/badge.svg)](https://github.com/shoo/voile/actions/workflows/main.yml)
[![downloads](https://img.shields.io/dub/dt/bsky.svg?cacheSeconds=3600)](https://code.dlang.org/packages/bsky)
[![BSL-1.0](http://img.shields.io/badge/license-BSL--1.0-blue.svg?style=flat)](./LICENSE)
[![codecov](https://codecov.io/gh/shoo/bsky/branch/main/graph/badge.svg)](https://codecov.io/gh/shoo/bsky)

# Abstract
The client library of [Bluesky](https://bsky.app/).

# Usage
```sh
dub add bsky
```

[API Documents](http://shoo.github.io/bsky)

# Examlple codes
```d
import std.stdio, std.process, std.range;
import bsky;
auto client = new Bluesky;
client.login(environment.get("BSKY_LOGINID"), environment.get("BSKY_LOGINPASS"));
scope (exit)
	client.logout();
foreach (post; client.timeline.take(100).toMessages)
	writeln(i"$(post.postBy.displayName) < $(post.text)");
```

[Examples](./examples)

# List of Supported API
| API                             | Supported functions |
|:--------------------------------|:--------------------|
| app.bsky.actor.getPreferences   | UNSUPPORTED |
| app.bsky.actor.getProfile       | bsky.client.Bluesky.getProfile <br /> bsky.client.Bluesky.profile |
| app.bsky.actor.getProfiles      | bsky.client.Bluesky.getProfiles <br /> bsky.client.Bluesky.fetchProfiles <br /> bsky.client.Bluesky.profiles |
| app.bsky.feed.getActorFeeds     | UNSUPPORTED |
| app.bsky.feed.getActorLikes     | UNSUPPORTED |
| app.bsky.feed.getAuthorFeed     | bsky.client.Bluesky.getAuthorFeed <br /> bsky.client.Bluesky.fetchAuthorFeed <br /> bsky.client.Bluesky.authorFeed |
| app.bsky.feed.getFeedGenerator  | UNSUPPORTED |
| app.bsky.feed.getFeedGenerators | UNSUPPORTED |
| app.bsky.feed.getFeed           | bsky.client.Bluesky.getFeed <br /> bsky.client.Bluesky.fetchFeed <br /> bsky.client.Bluesky.feed |
| app.bsky.feed.getLikes          | bsky.client.Bluesky.getLikes <br /> bsky.client.Bluesky.fetchLikeUsers <br /> bsky.client.Bluesky.likeUsers |
| app.bsky.feed.getListFeed       | bsky.client.Bluesky.getListFeed <br /> bsky.client.Bluesky.fetchListFeed <br /> bsky.client.Bluesky.listFeed |
| app.bsky.feed.getQuotes         | bsky.client.Bluesky.getQuotes <br /> bsky.client.Bluesky.fetchQuotedByPosts <br /> bsky.client.Bluesky.quotedByPosts |
| app.bsky.feed.getPostThread     | UNSUPPORTED |
| app.bsky.feed.getPosts          | bsky.client.Bluesky.getPosts <br /> bsky.client.Bluesky.fetchPosts <br /> bsky.client.Bluesky.getPostItems |
| app.bsky.feed.getRepostedBy     | bsky.client.Bluesky.getRepostedBy <br /> bsky.client.Bluesky.fetchRepostedBy <br /> bsky.client.Bluesky.repostedByUsers |
| app.bsky.feed.getSuggestedFeeds | UNSUPPORTED |
| app.bsky.feed.getTimeline       | bsky.client.Bluesky.getTimeline <br /> bsky.client.Bluesky.fetchTimeline <br /> bsky.client.Bluesky.timeline |
| app.bsky.feed.searchPosts       | bsky.client.Bluesky.searchPosts <br /> bsky.client.Bluesky.fetchSearchPosts <br /> bsky.client.Bluesky.searchPostItems |
| app.bsky.graph.getBlocks        | UNSUPPORTED |
| app.bsky.graph.getFollowers     | bsky.client.Bluesky.getFollowers <br /> bsky.client.Bluesky.fetchFollowers <br /> bsky.client.Bluesky.followers |
| app.bsky.graph.getFollows       | bsky.client.Bluesky.getFollows <br /> bsky.client.Bluesky.fetchFollows <br /> bsky.client.Bluesky.follows |
| app.bsky.graph.getListBlocks    | UNSUPPORTED |
| app.bsky.graph.getListMutes     | UNSUPPORTED |
| app.bsky.graph.getList          | UNSUPPORTED |
| app.bsky.graph.getLists         | UNSUPPORTED |
| app.bsky.graph.getMutes         | UNSUPPORTED |
| app.bsky.graph.getSuggestedFollowsByActor | UNSUPPORTED |
| app.bsky.graph.muteActorList    | UNSUPPORTED |
| app.bsky.graph.muteActor        | UNSUPPORTED |
| app.bsky.graph.unmuteActorList  | UNSUPPORTED |
| app.bsky.graph.unmuteActor      | UNSUPPORTED |
| app.bsky.labeler.getServices    | UNSUPPORTED |
| app.bsky.notification.getUnreadCount    | UNSUPPORTED |
| app.bsky.notification.listNotifications | UNSUPPORTED |
| app.bsky.notification.registerPush      | UNSUPPORTED |
| app.bsky.notification.updateSeen        | UNSUPPORTED |
| com.atproto.admin.deleteAccount         | UNSUPPORTED |
| com.atproto.admin.disableAccountInvites | UNSUPPORTED |
| com.atproto.admin.disableInviteCodes    | UNSUPPORTED |
| com.atproto.admin.enableAccountInvites  | UNSUPPORTED |
| com.atproto.admin.getAccountInfo        | UNSUPPORTED |
| com.atproto.admin.getInviteCodes        | UNSUPPORTED |
| com.atproto.admin.getSubjectStatus      | UNSUPPORTED |
| com.atproto.admin.updateAccountEmail    | UNSUPPORTED |
| com.atproto.admin.updateAccountHandle   | UNSUPPORTED |
| com.atproto.admin.updateAccountPassword | UNSUPPORTED |
| com.atproto.admin.updateSubjectStatus   | UNSUPPORTED |
| com.atproto.identity.getRecommendedDidCredentials | UNSUPPORTED |
| com.atproto.identity.requestPlcOperationSignature | UNSUPPORTED |
| com.atproto.identity.resolveHandle      | bsky.client.Bluesky.resolveHandle |
| com.atproto.identity.signPlcOperation   | UNSUPPORTED |
| com.atproto.identity.submitPlcOperation | UNSUPPORTED |
| com.atproto.identity.updateHandle       | UNSUPPORTED |
| com.atproto.moderation.createReport     | UNSUPPORTED |
| com.atproto.repo.applyWrites            | UNSUPPORTED |
| com.atproto.repo.createRecord           | bsky.client.Bluesky.createRecord <br /> bsky.client.Bluesky.sendPost <br /> bsky.client.Bluesky.sendReplyPost <br /> bsky.client.Bluesky.sendQuotePost <br /> bsky.client.Bluesky.markLike <br /> bsky.client.Bluesky.repost <br /> bsky.client.Bluesky.follow |
| com.atproto.repo.deleteRecord           | bsky.client.Bluesky.deletePost <br /> bsky.client.Bluesky.deleteLike <br /> bsky.client.Bluesky.deleteRepost <br /> bsky.client.Bluesky.unfollow |
| com.atproto.repo.getRecord              | bsky.client.Bluesky.getRecord |
| com.atproto.repo.importRepo             | UNSUPPORTED |
| com.atproto.repo.listMissingBlobs       | UNSUPPORTED |
| com.atproto.repo.listRecords            | bsky.client.Bluesky.listRecords <br /> bsky.client.Bluesky.fetchRecords <br /> bsky.client.Bluesky.listRecordItems |
| com.atproto.repo.putRecord              | UNSUPPORTED |
| com.atproto.repo.uploadBlob             | bsky.client.Bluesky.uploadBlob <br /> bsky.client.Bluesky.sendPost |
| com.atproto.server.activateAccount      | UNSUPPORTED |
| com.atproto.server.checkAccountStatus   | UNSUPPORTED |
| com.atproto.server.confirmEmail         | UNSUPPORTED |
| com.atproto.server.createAccount        | UNSUPPORTED |
| com.atproto.server.createAppPassword    | UNSUPPORTED |
| com.atproto.server.createInviteCode     | UNSUPPORTED |
| com.atproto.server.createInviteCodes    | UNSUPPORTED |
| com.atproto.server.createSession        | bsky.auth.AtprotoAuth.createSeession <br /> bsky.client.Bluesky.login |
| com.atproto.server.deactivateAccount    | UNSUPPORTED |
| com.atproto.server.deleteAccount        | UNSUPPORTED |
| com.atproto.server.deleteSession        | bsky.auth.AtprotoAuth.deleteSession <br /> bsky.client.Bluesky.logout |
| com.atproto.server.describeServer       | UNSUPPORTED |
| com.atproto.server.getAccountInviteCodes | UNSUPPORTED |
| com.atproto.server.getServiceAuth       | UNSUPPORTED |
| com.atproto.server.getSession           | bsky.auth.AtprotoAuth.updateSession |
| com.atproto.server.listAppPasswords     | UNSUPPORTED |
| com.atproto.server.refreshSession       | bsky.auth.AtprotoAuth.refreshSession <br /> bsky.auth.AtprotoAuth.updateSession |
| com.atproto.server.requestAccountDelete | UNSUPPORTED |
| com.atproto.server.requestEmailConfirmation | UNSUPPORTED |
| com.atproto.server.requestEmailUpdate   | UNSUPPORTED |
| com.atproto.server.requestPasswordReset | UNSUPPORTED |
| com.atproto.server.reserveSigningKey    | UNSUPPORTED |
| com.atproto.server.revokeAppPassword    | UNSUPPORTED |
| com.atproto.server.updateEmail          | UNSUPPORTED |
| com.atproto.sync.getBlob                | UNSUPPORTED |
| com.atproto.sync.getBlocks              | UNSUPPORTED |
| com.atproto.sync.getLatestCommit        | UNSUPPORTED |
| com.atproto.sync.getRecord              | UNSUPPORTED |
| com.atproto.sync.getRepo                | UNSUPPORTED |
| com.atproto.sync.listBlobs              | UNSUPPORTED |
| com.atproto.sync.listRepos              | UNSUPPORTED |
| tools.ozone.communication.createTemplate | UNSUPPORTED |
| tools.ozone.communication.deleteTemplate | UNSUPPORTED |
| tools.ozone.communication.listTemplates  | UNSUPPORTED |
| tools.ozone.communication.updateTemplate | UNSUPPORTED |
| tools.ozone.moderation.emitEvent        | UNSUPPORTED |
| tools.ozone.moderation.getEvent         | UNSUPPORTED |
| tools.ozone.moderation.getRecord        | UNSUPPORTED |
| tools.ozone.moderation.getRepo          | UNSUPPORTED |
| tools.ozone.moderation.queryEvents      | UNSUPPORTED |
| tools.ozone.moderation.queryStatuses    | UNSUPPORTED |
| tools.ozone.moderation.searchRepos      | UNSUPPORTED |

# LICENSE
Boost Software License - Version 1.0
- For detail is here: [LICENSE](./LICENSE)
