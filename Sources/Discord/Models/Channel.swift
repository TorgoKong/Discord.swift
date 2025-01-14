/**
The MIT License (MIT)

Copyright (c) 2023-present Defxult

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

import Foundation

/// Find the type of channel. If `nil`, it was not detected becaise it was most likely a new channel type that was recently added to the API
/// and has not been added to the lib yet.
func determineGuildChannelType(type: Int, data: JSON, bot: Bot, guildId: Snowflake) -> GuildChannel? {
    if let type = ChannelType(rawValue: type) {
        var temp: GuildChannel!
        switch type {
        case .guildText, .guildAnnouncement:
            temp = TextChannel(bot: bot, channelData: data, guildId: guildId)
            
        case .guildVoice:
            temp = VoiceChannel(bot: bot, vcData: data, guildId: guildId)
            
        case .guildCategory:
            temp = CategoryChannel(bot: bot, categoryData: data, guildId: guildId)
            
        case .announcementThread, .publicThread, .privateThread:
            temp = ThreadChannel(bot: bot, threadData: data, guildId: guildId)
            
        case .guildStageVoice:
            temp = StageChannel(bot: bot, scData: data, guildId: guildId)
            
        case .guildForum:
            temp = ForumChannel(bot: bot, fcData: data, guildId: guildId)
            
        case .dm:
            break
        }
        return temp
    }
    return nil
}

fileprivate func buildChannelOverwrites(_ overwrites: [JSON]) -> [PermissionOverwrites] {
    var ovrw = [PermissionOverwrites]()
    overwrites.forEach({ obj in
        ovrw.append(.init(overwriteData: obj))
    })
    return ovrw
}

/// Represents a channel where messages are able to be sent.
public protocol Messageable : Object {
    
    /// Your bot instance.
    var bot: Bot? { get }
}

extension Messageable {
    
    /// Delete multiple messages at once.
    /// - Parameters:
    ///   - toDelete: The messages to delete (2 minimum, 100 maximum). Messages older than 2 weeks will be ignored.
    ///   - reason: The reason for deleting the messages. This shows up in the guilds audit log.
    public func bulkDeleteMessages(_ toDelete: [Message], reason: String? = nil) async throws {
        try await bot!.http.bulkDeleteMessages(channelId: id, messagesToDelete: toDelete, reason: reason)
    }
    
    /// Delete messages matching the result of the given closure.
    /// - Parameters:
    ///   - matching: The closure to match messages against. If `true`, that message will be deleted.
    ///   - limit: The amount of messages to search through, max 100. This is typically not used as the amount of messages that will be deleted but can be used as such.
    ///   - bulk: Whether to delete all messages at once.
    ///   - search: What to search by. Either before, after, or around a specified message. If `nil`, no filter is used.
    ///   - reason: The reason for deleting the messages. This shows up in the guilds audit log.
    public func deleteAllMessages(
        matching: (Message) -> Bool,
        limit: Int = 100,
        bulk: Bool = true,
        search: Message.History? = nil,
        reason: String? = nil
    ) async throws {
        var toDelete = [Message]()
        for msg in try await history(limit: limit, search: search) {
            if matching(msg) {
                toDelete.append(msg)
            }
        }
        if bulk && toDelete.count >= 2 {
            try await bulkDeleteMessages(toDelete, reason: reason)
        } else {
            for msg in toDelete {
                try await msg.delete(reason: reason)
            }
        }
    }
    
    /// Receive the channels message history.
    /// - Parameters:
    ///   - limit: Max number of messages to return (1-100).
    ///   - search: What to search by. Either before, after, or around a specified message. If `nil`, no filter is used.
    /// - Returns: The messages matching the limit/search query.
    public func history(limit: Int = 50, search: Message.History? = nil) async throws -> [Message] {
        if let search {
            switch search {
            case .before(let beforeId):
                return try await bot!.http.getChannelMessages(channelId: id, limit: limit, before: beforeId)
            case .after(let afterId):
                return try await bot!.http.getChannelMessages(channelId: id, limit: limit, after: afterId)
            case .around(let aroundId):
                return try await bot!.http.getChannelMessages(channelId: id, limit: limit, around: aroundId)
            }
        }
        return try await bot!.http.getChannelMessages(channelId: id, limit: limit)
    }
    
    /// Request a message in the channel.
    /// - Parameter id: ID of the message.
    /// - Returns: The requested message.
    public func requestMessage(_ id: Snowflake) async throws -> Message {
        return try await bot!.http.getChannelMessage(channelId: self.id, messageId: id)
    }
    
    /// Send a message to the channel.
    /// - Parameters:
    ///   - content: The message contents.
    ///   - tts: Whether this message should be sent as a TTS message.
    ///   - embeds: Embeds attached to the message (10 max).
    ///   - allowedMentions: Controls the mentions allowed when this message is sent.
    ///   - ui: The UI for the message. Contains things such as a ``Button`` or ``SelectMenu``.
    ///   - files: Files to attach to the message.
    ///   - stickers: Stickers to attach to the message (3 max).
    ///   - reference: The message to reply to.
    ///   - silent: Whether this message suppresses push and desktop notifications.
    /// - Returns: The message that was sent.
    @discardableResult
    public func send(
        _ content: String? = nil,
        tts: Bool = false,
        embeds: [Embed]? = nil,
        allowedMentions: AllowedMentions = Bot.allowedMentions,
        ui: UI? = nil,
        files: [File]? = nil,
        stickers: [GuildSticker]? = nil,
        reference: Message.Reference? = nil,
        silent: Bool = false
    ) async throws -> Message {
        var payload: JSON = ["tts": tts, "allowed_mentions": allowedMentions.convert() ]
        
        if let content { payload["content"] = content }
        if let embeds { payload["embeds"] = Embed.convert(embeds) }
        if let reference { payload["message_reference"] = reference.convert() }
        if let ui { payload["components"] = try ui.convert() }
        if let stickers { payload["sticker_ids"] = stickers.map({ $0.id }) }
        if silent { payload["flags"] = Message.Flag.suppressNotifications.rawValue }
        
        // NOTE:
        // Suppressing embeds is intentionally excluded. I don't see the point of adding embeds just so they can
        // be suppressed. If a user is going to suppress embeds, why add them at all in the first place? Maybe
        // in the future there will be a reason for suppressing them, but for now I can't think of a good reason.
        
        let message = try await bot!.http.createMessage(channelId: id, json: payload, files: files)
        UI.setUI(message: message, ui: ui)
        return message
    }
    
    /**
     Trigger the typing indicator in the channel. Each trigger lasts 10 seconds unless a message is sent sooner. If you need more than 10 seconds, use the `while` parameter.
     
     ```swift
     try await channel.triggerTyping(while: {
        // Heavy lifting code...
     
        // After the "heavy lifting" is done, the last step is to send a message.
        // Once a message is sent, the typing indicator will be removed unless the
        // closure has not finished executing. If the closure has not returned, it
        // is assumed the "heavy lifting" is still in progress, and the typing indicator
        // will continue to be displayed. So sending a message should be the last line
        // to signal the closure will return as well as remove the typing indicator.
     
        try! await channel.send("...")
     })
     ```
     - Parameter while: Code block to execute. If the workload will take longer than 10 seconds, this will continuously display the typing indicator until a message is sent (see discussion).
     */
    public func triggerTyping(while: (() async -> Void)? = nil) async throws {
        if let closure = `while` {
            let task = Task {
                while true {
                    do { try Task.checkCancellation() }
                    catch { break }
                    try await bot!.http.triggerTypingIndicator(channelId: id)
                    
                    // The delay isn't 10s because once it hits the 10s mark, the "is typing"
                    // disappears and reappears. To avoid that, trigger the typing indicator
                    // just a little bit sooner so that it's continuous.
                    await sleep(9500)
                }
            }
            await closure()
            task.cancel()
        } else {
            try await bot!.http.triggerTypingIndicator(channelId: id)
        }
    }
}
 
/// Represents a basic channel.
public protocol Channel : Object {
    
    /// Your bot instance.
    var bot: Bot? { get }
    
    /// Channel ID.
    var id: Snowflake { get }
    
    /// Channel type.
    var type: ChannelType { get }
}

extension Channel {
    
    /// Whether the channel conforms to protocol ``Messageable``. This simply verifies if the channel can have
    /// messages sent to it. It does not verify if your bot has the proper permissions to send a message to that channel.
    public var isMessageable: Bool {
        if let _ = self as? Messageable { return true }
        return false
    }
    
    /// Deletes the channel or closes it if it's a ``DMChannel``.
    /// - Parameter reason: The reason for deleting the channel.
    /// - Requires: Permission ``Permission/manageChannels`` for the guild or ``Permission/manageThreads`` if the channel is a thread.
    public func delete(reason: String? = nil) async throws {
        try await bot!.http.deleteChannel(channelId: id, reason: reason)
    }
}

/// Represents a channel type.
public enum ChannelType : Int, CaseIterable {
    
    /// Represents a ``TextChannel`` type.
    case guildText
    
    /// Represents a ``DMChannel`` type.
    case dm
    
    /// Represents a ``VoiceChannel`` type.
    case guildVoice
    
    /// Represents a ``CategoryChannel`` type.
    case guildCategory = 4
    
    /// Represents a ``TextChannel`` type where announcements can be published.
    case guildAnnouncement
    
    /// Represents a ``ThreadChannel`` type where a thread is in an announcement channel.
    case announcementThread = 10
    
    /// Represents a public ``ThreadChannel`` type.
    case publicThread
    
    /// Represents a private ``ThreadChannel`` type.
    case privateThread
    
    /// Represents a ``StageChannel`` type.
    case guildStageVoice = 13
    
    /// Represents a ``ForumChannel`` type.
    case guildForum = 15
}

/// Represents a channel that's in a guild.
public protocol GuildChannel : Channel {
    
    /// The ID of the last message sent in this channel.
    var lastMessageId: Snowflake? { get }
    
    /// Permission overwrites for the channel. Intent ``Intents/guilds`` and ``Intents/guildMembers`` are required. If disabled, this will return `nil`.
    var overwrites: [PermissionOverwrites] { get }
    
    /// The channel name.
    var name: String { get }
    
    /// The ID of the guild the channel belongs to.
    var guildId: Snowflake { get }
    
    /// The ID of the category the channel belongs to.
    var categoryId: Snowflake? { get }
}

extension GuildChannel {
    
    /// The category the channel belongs to.
    public var category: CategoryChannel? { categoryId != nil ? guild.getChannel(categoryId!) as? CategoryChannel : nil }
    
    /// The guild the channel belongs to.
    public var guild: Guild { bot!.getGuild(guildId)! }
    
    /// Mention the channel.
    public var mention: String { type == .guildCategory ? name : Markdown.mentionChannel(id: id) }
    
    /// The direct URL for the channel.
    public var jumpUrl: String {
        let url = "https://discord.com/channels/\(guild.id)/\(id)"
        return Markdown.suppressLinkEmbed(url: url)
    }
    
    /// Whether the channel permissions are synced to its category. Will be `false` if not under a category.
    public var permissionsSynced: Bool {
        if let category {
            if let channel = bot!.getChannel(id) as? GuildChannel {
                return channel.overwrites == category.overwrites
            }
        }
        return false
    }
    
    /// Creates an invite for the channel.
    /// - Parameters:
    ///   - maxAge: Duration of invite in seconds before expiry, or ``Invite/infinite`` for never. Goes up to 7 days.
    ///   - maxUses: Max number of uses or ``Invite/infinite`` for unlimited.  100 maximum.
    ///   - temporary: Whether this invite only grants temporary membership.
    ///   - unique: If the invite URL should be unique. If `false`, there's a chance a previously created on could be created.
    ///   - targetType: The type of target for this voice channel invite.
    ///   - targetUser: The user whose stream to display for this invite. Required if `targetType` is ``Invite/Target/stream``, the user must be streaming in the channel.
    ///   - targetApplicationId: The ID of the embedded application to open for this invite. Required if `targetType` is ``Invite/Target/embeddedApplication``. The application must have the flag ``Application/Flag/embedded``.
    ///   - reason: The reason for creating the invite. This shows up in the guilds audit log.
    /// - Returns: The newly created invite.
    public func createInvite(
        maxAge: Int = Invite.twentyFourHours,
        maxUses: Int = Invite.infinite,
        temporary: Bool = false,
        unique: Bool = true,
        targetType: Invite.Target? = nil,
        targetUser: User? = nil,
        targetApplicationId: Snowflake? = nil,
        reason: String? = nil
    ) async throws -> Invite {
        try await bot!.http.createChannelInvite(
            channelId: id,
            maxAge: maxAge,
            maxUses: maxUses,
            temporary: temporary,
            unique: unique,
            targetType: targetType,
            targetUserId: targetUser?.id,
            targetApplicationId: targetApplicationId,
            reason: reason
        )
    }
    
    /// Deletes a channels permissions for a user or role.
    /// - Parameters:
    ///   - item: The ``Member`` or ``Role`` to delete permissions for.
    ///   - reason: The reason for deleting the permissions. This shows up in the guilds audit log.
    public func deletePermission(for item: Object, reason: String? = nil) async throws {
        try await bot!.http.deleteChannelPermission(channelId: id, userOrRoleId: item.id, reason: reason)
    }
    
    /// Get the channel overwrites.
    /// - Parameter for: The ``Member`` or ``Role`` to retrieve the overwrites for.
    /// - Returns: The overwrites matching the parameters.
    /// - Note: The method is only available for non-thread channels.
    public func getOverwrites(for item: Object) -> PermissionOverwrites? {
        overwrites.first(where: { $0.id == item.id })
    }
    
    /// Retrieve the invites for the channel.
    /// - Returns: All active invites for the channel.
    public func invites() async throws -> [Invite] {
        return try await bot!.http.getChannelInvites(channelId: id)
    }
    
    /// Update the channel overwrites.
    /// - Parameters:
    ///   - overwrites: The new overwrites.
    ///   - reason: The reason for updating the permissions. The shows up in the guilds audit log.
    /// - Note: The is only available for non-thread channels.
    public func updateOverwrites(_ overwrites: PermissionOverwrites, reason: String? = nil) async throws {
        guard !(self is ThreadChannel) else { return }
        try await bot!.http.editChannelPermissions(channelId: id, overwrites: overwrites, reason: reason)
    }
}

/// Represents a guild channel that can have messages sent to it.
public protocol GuildChannelMessageable: GuildChannel, Messageable { }

extension GuildChannelMessageable {
    
    /// Creates a webhook for the channel.
    /// - Parameters:
    ///   - name: Name of the webhook (1-80 characters). Cannot contain the substrings "clyde" or "discord" (case-insensitive).
    ///   - avatar: Avatar for the webhook.
    ///   - reason: The reason for creating the webhook. This shows up in the guilds audit log.
    /// - Returns: The newly created webhook.
    public func createWebhook(name: String, avatar: File? = nil, reason: String? = nil) async throws -> Webhook {
        return try await bot!.http.createWebhook(channelId: id, name: name, avatar: avatar, reason: reason)
    }
    
    /// Retrieve the webhooks in this channel.
    public func webhooks() async throws -> [Webhook] {
        return try await bot!.http.getChannelWebhooks(channelId: id)
    }
}

/// Represents a category.
public class CategoryChannel : GuildChannel, Hashable {

    /// ID of the category.
    public let id: Snowflake

    /// The channel type.
    public let type: ChannelType

    /// Sorting position of the channel.
    public internal(set) var position: Int

    /// The category name.
    public internal(set) var name: String

    /// Will always be `nil` for a category. This is only here for the overall usefulness of conforming to protocol ``GuildChannel``.
    public let lastMessageId: Snowflake? = nil

    /// Your bot instance.
    public weak private(set) var bot: Bot?
    
    /// Permission overwrites for the channel. Intent ``Intents/guilds`` and ``Intents/guildMembers`` are required. If disabled, this will be empty.
    public var overwrites: [PermissionOverwrites] { buildChannelOverwrites(overwriteData) }
    var overwriteData: [JSON]
    
    // ---------- API Separated ----------
    
    /// The channels that belong to the category.
    public var channels: [GuildChannel] { guild.channels.filter({ $0.categoryId == id && $0.type != .guildCategory }) }
    
    /// Will always be `nil` for a category. This is only here for the overall usefulness of conforming to protocol ``GuildChannel``.
    public let categoryId: Snowflake? = nil
    
    /// The ID of the guild the channel belongs to.
    public let guildId: Snowflake
    
    // -----------------------------------
    
    // Hashable
    public static func == (lhs: CategoryChannel, rhs: CategoryChannel) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(bot: Bot, categoryData: JSON, guildId: Snowflake) {
        self.bot = bot
        self.guildId = guildId
        id = Conversions.snowflakeToUInt(categoryData["id"])
        type = ChannelType(rawValue: categoryData["type"] as! Int)!
        position = categoryData["position"] as! Int
        overwriteData = categoryData["permission_overwrites"] as! [JSON]
        name = categoryData["name"] as! String
    }
    
    /// Edit the category channel.
    /// - Parameters:
    ///   - edits: The enum containing all values to be updated or removed for the category.
    ///   - reason: The reason for editing the category channel. This shows up in the guilds audit log.
    /// - Returns: The updated category channel.
    @discardableResult
    public func edit(_ edits: Edit..., reason: String? = nil) async throws -> CategoryChannel {
        guard !edits.isEmpty else { return self }
        
        var payload = JSON()
        
        for edit in edits {
            switch edit {
            case .name(let name):
                payload["name"] = name
            case .position(let position):
                payload["position"] = nullable(position)
            case .overwrites(let permOverwrites):
                payload["permission_overwrites"] = nullable(permOverwrites?.map({ $0.convert() }))
            }
        }
        return try await bot!.http.modifyChannel(channelId: id, guildId: guildId, json: payload, reason: reason) as! CategoryChannel
    }
}

extension CategoryChannel {
    
    /// Represents the values that can be edited in a ``CategoryChannel``.
    public enum Edit {
        
        /// The name of the category.
        case name(String)
        
        /// Sorting position of the category. Can be `nil` for automatic sorting.
        case position(Int?)
        
        /// Permission overwrites for members and role. Can be `nil` to remove overwrites.
        case overwrites([PermissionOverwrites]?)
    }
}

/// Represents a direct message channel.
public class DMChannel : Channel, Messageable, Hashable {
    
    /// ID of the channel.
    public let id: Snowflake
    
    /// The channel type. Will always be ``ChannelType/dm``.
    public let type: ChannelType = .dm
    
    /// The ID of the last message sent in this channel.
    public internal(set) var lastMessageId: Snowflake?
    
    /// The ID of the user in the channel.
    public internal(set) var recipientId: Snowflake?

    /// Your bot instance.
    public weak private(set) var bot: Bot?
    
    // Hashable
    public static func == (lhs: DMChannel, rhs: DMChannel) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(bot: Bot, dmData: JSON) {
        self.bot = bot
        id = Conversions.snowflakeToUInt(dmData["id"])
        lastMessageId = Conversions.snowflakeToOptionalUInt(dmData["last_message_id"])

        // Not sure why discord makes this as an optional...
        if let arrayUserObject = dmData["recipients"] as? [JSON] {
            
            // Theres only 1 user in the array.
            let userObj = arrayUserObject[0]
            recipientId = Conversions.snowflakeToUInt(userObj["id"])
        }
    }
    
    /// Get the messages pinned to the channel.
    /// - Returns: The messages pinned to the channel.
    public func pins() async throws -> [Message] {
        return try await bot!.http.getPinnedMessages(channelId: id)
    }
}

/// Represents a text channel.
public class TextChannel : GuildChannelMessageable, Hashable {

    /// ID of the channel.
    public let id: Snowflake
    
    /// The channel type.
    public let type: ChannelType
    
    /// Sorting position of the channel.
    public internal(set) var position: Int
    
    /// The channel name.
    public internal(set) var name: String
    
    /// The channel topic.
    public internal(set) var topic: String?
    
    /// Whether the channel is NSFW.
    public internal(set) var isNsfw: Bool
    
    /// The ID of the last message sent in this channel.
    public internal(set) var lastMessageId: Snowflake?
    
    /// Amount of seconds a user has to wait before sending another message (0-21600).
    public internal(set) var slowmodeDelay: Int

    // docs set in `GuildChannel`
    public internal(set) var categoryId: Snowflake?
    
    /// When the last pinned message was pinned.
    public internal(set) var lastPinned: Date?
    
    /// Permission overwrites for the channel. Intent ``Intents/guilds`` and ``Intents/guildMembers`` are required. If disabled, this will be empty.
    public var overwrites: [PermissionOverwrites] { buildChannelOverwrites(overwriteData) }
    var overwriteData: [JSON]

    /// Your bot instance.
    public weak private(set) var bot: Bot?

    // ------------------------------ API Separated -----------------------------------

    /// Whether the channel is an announcement channel.
    public var isAnnouncement: Bool { type == .guildAnnouncement }
    
    /// The ID of the guild the channel belongs to.
    public let guildId: Snowflake
    
    // --------------------------------------------------------------------------------
    
    // Hashable
    public static func == (lhs: TextChannel, rhs: TextChannel) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(bot: Bot, channelData: JSON, guildId: Snowflake) {
        self.bot = bot
        self.guildId = guildId
        id = Conversions.snowflakeToUInt(channelData["id"])
        type = ChannelType(rawValue: channelData["type"] as! Int)!
        position = channelData["position"] as! Int
        overwriteData = channelData["permission_overwrites"] as! [JSON]
        name = channelData["name"] as! String
        topic = channelData["topic"] as? String
        isNsfw = Conversions.optionalBooltoBool(channelData["nsfw"])
        lastMessageId = Conversions.snowflakeToOptionalUInt(channelData["last_message_id"])
        slowmodeDelay = channelData["rate_limit_per_user"] as? Int ?? 0
        categoryId = Conversions.snowflakeToOptionalUInt(channelData["parent_id"])

        if let whenPinned = channelData["last_pin_timestamp"] as? String {
            lastPinned = Conversions.stringDateToDate(iso8601: whenPinned)
        }
    }
    
    /**
     Receive the archived threads in the channel.
     
     Below is an example on how to request archived threads:
     ```swift
     do {
         for try await threads in channel.archivedThreads() {
             // ...
         }
     } catch {
         // Handle error
     }
     ```
     Each iteration of the for-loop contains batched threads. Meaning `threads` will be an array of at most 50 threads. You will receive batched threads until
     all threads matching the method parameters are fully received.
     
     - Parameters:
        - before: Returns threads before this date.
        - limit: The amount of threads to retrieve.
        - private: Whether to retrieve private archived threads.
        - joined: Whether to retrieve private archived threads that you’ve joined. You cannot set this to `true` and `private` to `false`.
     - Returns: The threads matching the parameters.
     - Note: Setting parameters `joined` & `private` to `true`, parameter `joined` will take priority.
     */
    public func archivedThreads(before: Date = .now, limit: Int = 50, joined: Bool = false, private: Bool = false) -> AsyncArchivedThreads {
        return AsyncArchivedThreads(channel: self, limit: limit, before: before, joined: joined, private: `private`)
    }
    
    /// Create a thread.
    /// - Parameters:
    ///   - name: Name of the thread.
    ///   - autoArchiveDuration: Duration to automatically archive the thread after recent activity.
    ///   - slowmode: Amount of seconds a user has to wait before sending another message.
    ///   - invitable: Whether non-moderators can add other non-moderators to a thread. Only available when creating a private thread.
    ///   - reason: The reason for creating the thread. This shows up in the guilds audit log.
    /// - Returns: The newly created thread.
    public func createThread( // Note: This is considered a private thread. Public threads are created via Message.createThread()
        name: String,
        autoArchiveDuration: ThreadChannel.ArchiveDuration = .twentyfourHours,
        slowmode: Int? = nil,
        invitable: Bool = true,
        reason: String? = nil
    ) async throws -> ThreadChannel {
        return try await bot!.http.startThreadWithoutMessage(
            channelId: id,
            guildId: guildId,
            threadName: name,
            autoArchiveDuration: autoArchiveDuration,
            slowmodeInSeconds: slowmode,
            invitable: invitable,
            reason: reason
        )
    }
    
    /// Edit the text channel.
    /// - Parameters:
    ///   - edits: The enum containing all values to be updated or removed for the text channel.
    ///   - reason: The reason for editing the text channel. This shows up in the guilds audit log.
    /// - Returns: The updated text channel.
    @discardableResult
    public func edit(_ edits: Edit..., reason: String? = nil) async throws -> TextChannel {
        guard !edits.isEmpty else { return self }
        
        var payload = JSON()
        
        for edit in edits {
            switch edit {
            case .name(let name):
                payload["name"] = name
            case .position(let position):
                payload["position"] = nullable(position)
            case .overwrites(let permOverwrites):
                payload["permission_overwrites"] = nullable(permOverwrites?.map({ $0.convert() }))
            case .type(let type):
                payload["type"] = type.rawValue
            case .topic(let topic):
                payload["topic"] = nullable(topic)
            case .nsfw(let nsfw):
                payload["nsfw"] = nsfw
            case .slowmodeDelay(let slowmode):
                payload["rate_limit_per_user"] = slowmode < 0 ? 0 : slowmode
            case .category(let category):
                payload["parent_id"] = nullable(category?.id)
            }
        }
        return try await bot!.http.modifyChannel(channelId: id, guildId: guildId, json: payload, reason: reason) as! TextChannel
    }
    
    /// Follow the text channel.
    /// - Parameter sendUpdatesTo: The channel where messages will be sent when they are published.
    /// - Returns: A webhook associated with the announcement channel.
    public func follow(sendUpdatesTo: TextChannel) async throws -> Webhook {
        // The discord error message isn't helpful here (invalid form body)
        if type != .guildAnnouncement { throw HTTPError.badRequest("Cannot follow non-announcement channels") }
        
        return try await bot!.http.followAnnouncementChannel(channelToFollow: id, sendMessagesTo: sendUpdatesTo.id)
    }
    
    /// Get all messages pinned to the channel.
    /// - Returns: All pinned messages in the channel.
    public func pins() async throws -> [Message] {
        return try await bot!.http.getPinnedMessages(channelId: id)
    }
}

extension TextChannel {

    /// Represents the values that can be edited in a ``TextChannel``.
    public enum Edit {

        /// The name of the channel.
        case name(String)

        /// The type of channel. Only conversion between channels that are of type ``ChannelType/guildText`` & ``ChannelType/guildAnnouncement`` are supported and only in guilds that have the ``Guild/Feature/news`` feature.
        case type(ChannelType)
        
        /// Sorting position of the channel. Can be `nil` for automatic sorting.
        case position(Int?)
        
        /// The channel topic. Can be `nil` to remove the topic.
        case topic(String?)
        
        /// Whether the channel is NSFW.
        case nsfw(Bool)
        
        /// Amount of seconds a user has to wait before sending another message (0-21600).
        case slowmodeDelay(Int)
        
        /// Permission overwrites for members and role. Can be `nil` to remove all overwrites.
        case overwrites([PermissionOverwrites]?)
        
        /// The category the channel belongs to. Can be `nil` to remove it from a category.
        case category(CategoryChannel?)
    }
}

/// Represents an asynchronous iterator used for requesting archived threads in a ``TextChannel`` or ``ForumChannel``.
public struct AsyncArchivedThreads : AsyncSequence, AsyncIteratorProtocol {
    
    public typealias Element = [ThreadChannel]

    let channel: GuildChannel
    let joined: Bool
    let `private`: Bool
    let before: Date
    let indefinite = -1
    var remaining = 0
    var hasMore = true

    init(channel: GuildChannel, limit: Int?, before: Date, joined: Bool, private: Bool) {
        self.channel = channel
        self.joined = joined
        self.before = before
        self.private = `private`
        self.remaining = limit ?? indefinite
    }
    
    private func req(limit: Int, before: Date, joined: Bool, private: Bool) async throws -> JSON {
        return try await channel.bot!.http.getPublicPrivateJoinedArchivedThreads(channelId: channel.id, before: before, limit: limit, joined: joined, private: `private`)
    }
    
    public mutating func next() async throws -> Element? {
        if !hasMore { return nil }
        
        var threads = [ThreadChannel]()
        let requestAmount = (remaining == indefinite ? 50 : Swift.min(remaining, 50))
        let data = try await req(limit: requestAmount, before: before, joined: joined, private: `private`)
        let threadObjs = data["threads"] as! [JSON]
        
        if (data["has_more"] as! Bool) == false {
            hasMore = false
        }
        
        // If the amount of members received is less 50, theres no more data after it, so set
        // this to false to prevent an extra HTTP request that is not needed.
        if threadObjs.count < 50 {
            hasMore = false
        }
        
        for obj in threadObjs {
            threads.append(.init(bot: channel.bot!, threadData: obj, guildId: channel.guildId))
            if remaining != indefinite {
                remaining -= 1
                if remaining == 0 {
                    hasMore = false
                    return threads
                }
            }
        }
        return threads
    }
    
    public func makeAsyncIterator() -> AsyncArchivedThreads {
        self
    }
}

/// Represents a forum channel.
public class ForumChannel : GuildChannel, Hashable {

    /// ID of the channel.
    public let id: Snowflake
    
    /// The channel type.
    public let type: ChannelType

    /// Sorting position of the channel.
    public internal(set) var position: Int
    
    /// The channel name.
    public internal(set) var name: String

    /// The channel topic.
    public internal(set) var topic: String?
    
    /// Whether the channel is NSFW.
    public internal(set) var isNsfw: Bool

    /// The ID of the last **thread** created in this channel.
    public internal(set) var lastMessageId: Snowflake?
    
    /// Amount of seconds a user has to wait before sending another message.
    public internal(set) var slowmodeDelay: Int
    
    // docs set in `GuildChannel`
    public internal(set) var categoryId: Snowflake?
    
    /// The set of tags that can be used.
    public internal(set) var tags = [Tag]()
    
    /// The channels flag.
    public internal(set) var flag: Flag?
    
    /// Permission overwrites for the channel. Intent ``Intents/guilds`` and ``Intents/guildMembers`` are required. If disabled, this will be empty.
    public var overwrites: [PermissionOverwrites] { buildChannelOverwrites(overwriteData) }
    var overwriteData: [JSON]
    
    /// Your bot instance.
    public weak private(set) var bot: Bot?
    
    // ---------- API Separated ----------
    
    /// The ID of the guild the channel belongs to.
    public let guildId: Snowflake
    
    // -----------------------------------
    
    // Hashable
    public static func == (lhs: ForumChannel, rhs: ForumChannel) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    
    init(bot: Bot, fcData: JSON, guildId: Snowflake) {
        self.bot = bot
        self.guildId = guildId
        id = Conversions.snowflakeToUInt(fcData["id"])
        type = ChannelType(rawValue: fcData["type"] as! Int)!
        position = fcData["position"] as! Int
        overwriteData = (fcData["permission_overwrites"] as! [JSON])
        name = fcData["name"] as! String
        topic = fcData["topic"] as? String
        isNsfw = fcData["nsfw"] as? Bool ?? false
        lastMessageId = Conversions.snowflakeToOptionalUInt(fcData["last_message_id"])
        slowmodeDelay = fcData["rate_limit_per_user"] as! Int
        categoryId = Conversions.snowflakeToOptionalUInt(fcData["parent_id"])
        
        if let tagObjs = fcData["available_tags"] as? [JSON] {
            for tagObj in tagObjs {
                tags.append(Tag(tagData: tagObj))
            }
        }
        
        if let flagValue = fcData["flags"] as? Int {
            flag = Flag(rawValue: flagValue)
        }
    }
    
    /**
     Receive the archived threads in the channel.
     
     Below is an example on how to request archived threads:
     ```swift
     do {
         for try await threads in channel.archivedThreads() {
             // ...
         }
     } catch {
         // Handle error
     }
     ```
     Each iteration of the for-loop contains batched threads. Meaning `threads` will be an array of at most 50 threads. You will receive batched threads until
     all threads matching the method parameters are fully received.
     
     - Parameters:
        - before: Returns threads before this date.
        - limit: The amount of threads to retrieve.
        - joined: Whether to retrieve private archived threads that you’ve joined. You cannot set this to `true` and `private` to `false`.
        - private: Whether to retrieve private archived threads.
     - Returns: The threads matching the parameters.
     - Note: Setting parameters `joined` & `private` to `true`, parameter `joined` will take priority.
     */
    public func archivedThreads(before: Date = .now, limit: Int = 50, joined: Bool = false, private: Bool = false) -> AsyncArchivedThreads {
        return AsyncArchivedThreads(channel: self, limit: limit, before: before, joined: joined, private: `private`)
    }
    
    /// Creates a thread.
    /// - Parameters:
    ///   - name: Name of the thread.
    ///   - autoArchiveDuration: The threads auto archive duration.
    ///   - slowmode: The threads slowmode.
    ///   - appliedTags: The tags that will be applied to the thread.
    ///   - content: The message contents.
    ///   - embeds: Embeds attached to the message (10 max).
    ///   - allowedMentions: Controls the mentions allowed when this message is sent.
    ///   - ui: The UI for the message. Contains things such as a ``Button`` or ``SelectMenu``.
    ///   - stickers: The stickers for the message.
    ///   - files: Files to attach to the message.
    ///   - suppressEmbeds: Whether to suppress embeds. If `true`, no embeds will be sent with the message.
    ///   - reason: The reason for creating the thread. This shows up the the guilds audit log.
    /// - Returns: The newly created thread.
    /// - Note: A message is required to be sent with the creation of a thread. Meaning at least one parameter such as `content`, `embeds`, `ui`, `stickers`, or `files` must be used.
    public func createThread(
        name: String,
        autoArchiveDuration: ThreadChannel.ArchiveDuration = .twentyfourHours,
        slowmode: Int? = nil,
        appliedTags: [ForumChannel.Tag]? = nil,
        
        // Forum Thread Message params
        content: String? = nil,
        embeds: [Embed]? = nil,
        allowedMentions: AllowedMentions = Bot.allowedMentions,
        ui: UI? = nil,
        stickers: [GuildSticker]? = nil,
        files: [File]? = nil,
        
        suppressEmbeds: Bool = false,
        reason: String? = nil
    ) async throws -> ThreadChannel {
        var payload: JSON = ["name": name, "auto_archive_duration": autoArchiveDuration.rawValue]
        
        if let slowmode { payload["rate_limit_per_user"] = slowmode }
        if let appliedTags { payload["applied_tags"] = appliedTags.map({ $0.id }) }
        
        // Message is required
        var messageObj: JSON = ["allowed_mentions": allowedMentions.convert()]
        
        if let content { messageObj["content"] = content }
        if let embeds { messageObj["embeds"] = embeds.map({ $0.convert() }) }
        if let ui { messageObj["components"] = try ui.convert() }
        if let stickers { messageObj["sticker_ids"] = stickers.map({ $0.id }) }
        if suppressEmbeds { messageObj["flags"] = Message.Flag.suppressEmbeds.rawValue }
        
        payload["message"] = messageObj
        
        let info = try await bot!.http.startThreadInForumChannel(
            channelId: id,
            guildId: guildId,
            name: name,
            archiveDuration: autoArchiveDuration,
            slowmode: slowmode,
            forumThreadMessage: payload,
            files: files
        )
        
        guild.cacheChannel(info.thread)
        UI.setUI(message: info.message, ui: ui)
        return info.thread
    }
    
    /// Edit the forum channel.
    /// - Parameters:
    ///   - edits: The enum containing all values to be updated or removed for the forum channel.
    ///   - reason: The reason for editing the forum channel. This shows up in the guilds audit log.
    /// - Returns: The updated forum channel.
    @discardableResult
    public func edit(_ edits: Edit..., reason: String? = nil) async throws -> ForumChannel {
        guard !edits.isEmpty else { return self }

        var payload = JSON()

        for edit in edits {
            switch edit {
            case .name(let name):
                payload["name"] = name
            case .defaultThreadAutoArchiveDuration(let dtad):
                payload["default_auto_archive_duration"] = dtad.rawValue
            case .defaultReactionEmoji(let partial):
                payload["default_reaction_emoji"] = nullable(partial?.convert())
            case .topic(let topic):
                payload["topic"] = nullable(topic)
            case .position(let position):
                payload["position"] = nullable(position)
            case .nsfw(let nsfw):
                payload["nsfw"] = nsfw
            case .overwrites(let permOverwrites):
                payload["permission_overwrites"] = nullable(permOverwrites?.map({ $0.convert() }))
            case .category(let category):
                payload["parent_id"] = nullable(category?.id)
            case .slowmode(let slowmode):
                payload["default_thread_rate_limit_per_user"] = slowmode
            case .threadCreationSlowmode(let creationSlowmode):
                payload["rate_limit_per_user"] = creationSlowmode
            case .availableTags(let tags):
                payload["available_tags"] = tags.map({ $0.convert() })
            case .sortOrder(let order):
                payload["default_sort_order"] = order.rawValue
            case .layout(let layout):
                payload["default_forum_layout"] = layout.rawValue
            }
        }
        return try await bot!.http.modifyChannel(channelId: id, guildId: guildId, json: payload, reason: reason) as! ForumChannel
    }
}

extension ForumChannel {
    
    /// Represents the values that can be edited in a ``ForumChannel``.
    public enum Edit {
        
        /// Name of the forum.
        case name(String)
        
        /// The amount of time threads will stop showing in the channel list after the specified period of inactivity.
        case defaultThreadAutoArchiveDuration(ThreadChannel.ArchiveDuration)
        
        /// The emoji to show in the add reaction button on a thread.
        case defaultReactionEmoji(PartialEmoji?)
        
        /// This is shown in the "Guidelines" section within the Discord app.
        case topic(String?)
        
        /// Sorting position of the channel. Can be `nil` for automatic sorting.
        case position(Int?)
        
        /// Whether the channel is NSFW.
        case nsfw(Bool)
        
        /// Explicit permission overwrites for ``Member``s and ``Role``s. Can be `nil` to remove all overwrites.
        case overwrites([PermissionOverwrites]?)
        
        /// The category the channel should be placed in.
        case category(CategoryChannel?)
    
        /// Amount of seconds a user has to wait before sending another message.
        case slowmode(Int)
    
        /// Amount of seconds a user has to wait before creating another thread.
        case threadCreationSlowmode(Int)
    
        /// A set of tags that have been applied to a thread.
        case availableTags([ForumChannel.Tag])
    
        /// The default sort order used to order posts.
        case sortOrder(ForumChannel.SortOrder)
    
        /// The default forum layout view used to display posts.
        case layout(ForumChannel.Layout)
    }
    
    /// Represents the channels flags.
    public enum Flag : Int {
        
        /// This thread is pinned.
        case pinned = 2
        
        /// Whether a tag is required to be specified when creating a thread in a forum channel.
        case requireTag = 16
    }
    
    /// Represents the Forums layout.
    public enum Layout : Int {
        
        /// No default has been set for forum channel.
        case notSet
        
        /// Display posts as a list.
        case listView
        
        /// Display posts as a collection of tiles.
        case galleryView
    }
    
    /// Represents the sort order for the Forums threads.
    public enum SortOrder : Int {
        
        /// Sort forum posts by activity.
        case latestActivity
        
        /// Sort forum posts by creation time (from most recent to oldest).
        case creationDate
    }
    
    /// Represents a Forum channel tag.
    public struct Tag {
        
        /// The ID of the tag. If manually created, this will be 0.
        public let id: Snowflake
        
        /// The name of the tag (20 characters max).
        public let name: String
        
        /// Whether this tag can only be added to or removed from threads by a member with the ``Permission/manageThreads`` permission.
        public let isModerated: Bool
        
        /// Emoji for the tag.
        public let emoji: PartialEmoji
        
        init(tagData: JSON) {
            id = Conversions.snowflakeToUInt(tagData["id"])
            name = tagData["name"] as! String
            isModerated = tagData["moderated"] as! Bool
                        
            // From discord: At most one of emoji_id and emoji_name may be set to a non-null value.
            if let _ = tagData["emoji_id"] as? String {
                emoji = PartialEmoji(partialEmojiData: [
                    "id": tagData["id"] as Any,
                    "name": name
                ])
            }
            else { emoji = PartialEmoji(tagData["emoji_name"] as! String) }
        }
        
        /// Initialize a Forum tag.
        /// - Parameters:
        ///   - name: The name of the tag (20 characters max).
        ///   - moderated: Whether this tag can only be added to or removed from threads by a member with the ``Permission/manageThreads`` permission.
        ///   - emoji: Emoji for the tag.
        public init(name: String, moderated: Bool, emoji: PartialEmoji) {
            id = 0
            self.name = name
            self.isModerated = moderated
            self.emoji = emoji
        }
        
        func convert() -> JSON {
            var payload: JSON = [
                "id": id,
                "name": name,
                "moderated": isModerated
            ]
            if let emojiId = emoji.id {
                payload["emoji_id"] = emojiId
                payload["emoji_name"] = NIL
            } else {
                payload["emoji_name"] = emoji.name!
                payload["emoji_id"] = NIL
            }
            return payload
        }
    }
}

/// Represents a voice channel.
public class VoiceChannel : GuildChannelMessageable, Hashable {
    
    /// ID of the channel.
    public let id: Snowflake
    
    /// The channel type.
    public let type: ChannelType
    
    /// Sorting position of the channel.
    public internal(set) var position: Int

    /// The channel name.
    public internal(set) var name: String

    /// The ID of the last message sent in this channel.
    public internal(set) var lastMessageId: Snowflake?

    // docs set in `GuildChannel`
    public internal(set) var categoryId: Snowflake?
    
    /// The bitrate (in bits) of the voice channel.
    public internal(set) var bitrate: Int
    
    /// The amount of users that are allowed in the voice channel.
    public internal(set) var userLimit: Int
    
    /// Voice region ID for the voice channel.
    public internal(set) var rtcRegion: RtcRegion?
    
    /// Permission overwrites for the channel. Intent ``Intents/guilds`` and ``Intents/guildMembers`` are required. If disabled, this will be empty.
    public var overwrites: [PermissionOverwrites] { buildChannelOverwrites(overwriteData) }
    var overwriteData: [JSON]

    /// Your bot instance.
    public weak private(set) var bot: Bot?
    
    // Hashable
    public static func == (lhs: VoiceChannel, rhs: VoiceChannel) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    
    
    // ---------------- API Separated ----------------
    
    /// The ID of the guild the channel belongs to.
    public let guildId: Snowflake
    
    /// The members currently in the channel.
    public var members: [Member] {
        var members = [Member]()
        for userId in guild.voiceStates.map({ $0.userId }) {
            if let member = guild.getMember(userId) {
                members.append(member)
            }
        }
        
        // `VoiceState` comes with a member object. This should be appended to the `members`
        // array because the above logic is dependent on whether the member is in the cache.
        // If a member was not cached, and then joins a voice channel, they will not be apart of
        // `members` because `guild.getMember()` would return `nil`. Since `VoiceState` comes with
        // their member object, add it to the total `members`. Also, since there's a chance the member
        // was already cached, remove any duplicates of `members` and `voiceStateMembers` with a `Set`
        let voiceStateMembers = guild.voiceStates.compactMap({ $0.member })
        members = [Member](Set<Member>(members + voiceStateMembers))
        
        return members
    }
    
    // -----------------------------------------------

    init(bot: Bot, vcData: JSON, guildId: Snowflake) {
        self.bot = bot
        self.guildId = guildId
        id = Conversions.snowflakeToUInt(vcData["id"])
        type = ChannelType(rawValue: vcData["type"] as! Int)!
        position = vcData["position"] as! Int
        overwriteData = vcData["permission_overwrites"] as! [JSON]
        lastMessageId = Conversions.snowflakeToOptionalUInt(vcData["last_message_id"])
        categoryId = Conversions.snowflakeToOptionalUInt(vcData["parent_id"])

        name = vcData["name"] as! String
        bitrate = vcData["bitrate"] as! Int
        userLimit = vcData["user_limit"] as! Int

        // If the region is missing, that means it's .automatic
        let rtcValue = (vcData["rtc_region"] as? String) ?? String.empty
        rtcRegion = RtcRegion(rawValue: rtcValue)
    }
    
    /// Edit the voice channel.
    /// - Parameters:
    ///   - edits: The enum containing all values to be updated or removed for the voice channel.
    ///   - reason: The reason for editing the voice channel. This shows up in the guilds audit log.
    /// - Returns: The updated voice channel.
    @discardableResult
    public func edit(_ edits: Edit..., reason: String? = nil) async throws -> VoiceChannel {
        guard !edits.isEmpty else { return self }

        var payload = JSON()

        for edit in edits {
            switch edit {
            case .bitrate(let bitrate):
                payload["bitrate"] = bitrate
            case .category(let category):
                payload["parent_id"] = nullable(category?.id)
            case .name(let name):
                payload["name"] = name
            case .position(let position):
                payload["position"] = nullable(position)
            case .region(let region):
                payload["rtc_region"] = region == .automatic ? NIL : region.rawValue
            case .userLimit(let userLimit):
                payload["user_limit"] = nullable(userLimit)
            case .overwrites(let permOverwrites):
                payload["permission_overwrites"] = nullable(permOverwrites?.map({ $0.convert() }))
            case .videoQualityMode(let quality):
                payload["video_quality_mode"] = quality.rawValue
            }
        }
        return try await bot!.http.modifyChannel(channelId: id, guildId: guildId, json: payload, reason: reason) as! VoiceChannel
    }
}

extension VoiceChannel {

    /// Represents the values that can be edited in a ``VoiceChannel``.
    public enum Edit {
        
        /// The bitrate (in bits) of the voice channel.
        ///
        /// Bitrates for guilds:
        /// - Normal guilds can set bitrate up to 96000.
        /// - Guilds with Boost level 1 can set up to 128000.
        /// - Guilds with Boost level 2 can set up to 256000.
        /// - Guilds with Boost level 3 or has the ``Guild/Feature/vipRegions`` feature can set up to 384000.
        case bitrate(Int)
        
        /// The category the channel belongs to. Can be `nil` for no category.
        case category(CategoryChannel?)
        
        /// The channel name.
        case name(String)
        
        /// Sorting position of the channel. Can be `nil` for automatic sorting.
        case position(Int?)
        
        /// Voice region ID for the voice channel.
        case region(RtcRegion)
        
        /// The amount of users that are allowed in the voice channel.
        case userLimit(Int?)
        
        /// Permission overwrites for members and role. Can be `nil` to remove all overwrites.
        case overwrites([PermissionOverwrites]?)

        /// The camera video quality mode of the voice channel.
        case videoQualityMode(VideoQualityMode)
    }

    /// Represents the voice channels region.
    public enum RtcRegion : String {
        case automatic = ""
        case brazil = "brazil"
        case hongKong = "hongkong"
        case india = "india"
        case japan = "japan"
        case rotterdam = "rotterdam"
        case russia = "russia"
        case singapore = "singapore"
        case southAfrica = "southafrica"
        case sydney = "sydney"
        case usCentral = "us-central"
        case usEast = "us-east"
        case usSouth = "us-south"
        case usWest = "us-west"
    }

    /// Represents the camera video quality for all channel participants.
    public enum VideoQualityMode : Int {
        
        /// Discord chooses the quality for optimal performance.
        case auto = 1
        
        /// 720p
        case full
    }

    /// Represent a user's voice connection status.
    public class State : Updateable {
        
        /// The channel the user is connected to.
        public internal(set) var channel: VoiceChannel?
        
        /// The user ID this voice state is for.
        public let userId: Snowflake
        
        /// The session ID for this voice state.
        public let sessionId: String
        
        /// The guild ID this voice state belongs to.
        public let guildId: Snowflake
        
        /// The member this voice state is for.
        public private(set) var member: Member?
        
        /// Whether this user is deafened by the guild.
        public internal(set) var isGuildDeafened: Bool
        
        /// Whether this user is muted by the guild.
        public internal(set) var isGuildMuted: Bool
        
        /// Whether this user is locally deafened.
        public internal(set) var isSelfDeafened: Bool
        
        /// Whether this user is locally muted.
        public internal(set) var isSelfMuted: Bool
        
        /// Whether this user is streaming using "Go Live".
        public internal(set) var isStreaming: Bool
        
        /// Whether this user's camera is enabled.
        public internal(set) var isCameraEnabled: Bool
        
        /// Whether this user is muted by the current user.
        public internal(set) var isSuppressed: Bool
        
        /// The time at which the user requested to speak.
        public internal(set) var requestedToSpeakAt: Date?
        
        // ---------- API Separated ----------
        
        /// The user this voice state is for.
        public var user: User? { bot!.getUser(userId) }
        
        /// The guild this voice state belongs to.
        public var guild: Guild { bot!.getGuild(guildId)! }
        
        // -----------------------------------
        
        private weak var bot: Bot?

        init(bot: Bot, voiceStateData: JSON, guildId: Snowflake) {
            self.bot = bot
            self.guildId = guildId
            let channelId = Conversions.snowflakeToOptionalUInt(voiceStateData["channel_id"])
            if let chId = channelId {
                channel = bot.getChannel(chId) as? VoiceChannel
            }
            if let memberObj = voiceStateData["member"] as? JSON {
                member = .init(bot: bot, memberData: memberObj, guildId: guildId)
            }
            
            userId = Conversions.snowflakeToUInt(voiceStateData["user_id"])
            sessionId = voiceStateData["session_id"] as! String
            isGuildDeafened = voiceStateData["deaf"] as! Bool
            isGuildMuted = voiceStateData["mute"] as! Bool
            isSelfDeafened = voiceStateData["self_deaf"] as! Bool
            isSelfMuted = voiceStateData["self_mute"] as! Bool
            isStreaming = Conversions.optionalBooltoBool(voiceStateData["self_stream"])
            isCameraEnabled = voiceStateData["self_video"] as! Bool
            isSuppressed = voiceStateData["suppress"] as! Bool
            
            let requestDate = voiceStateData["request_to_speak_timestamp"] as? String
            requestedToSpeakAt = requestDate != nil ? Conversions.stringDateToDate(iso8601: requestDate!) : nil
        }
        
        func update(_ data: JSON) {
            for (k, v) in data {
                switch k {
                case "channel_id":
                    let channelId = Conversions.snowflakeToOptionalUInt(v)
                    
                    // If a channel ID exists, that means they joined or was moved. If nil, they left, so remove the state from the cache.
                    if let channelId { channel = bot!.getChannel(channelId) as? VoiceChannel }
                    else {
                        if let channel {
                            if let idx = channel.guild.voiceStates.firstIndex(where: { $0.sessionId == sessionId }) {
                                channel.guild.voiceStates.remove(at: idx)
                                continue
                            }
                        }
                    }
                case "deaf":
                    isGuildDeafened = v as! Bool
                case "mute":
                    isGuildMuted = v as! Bool
                case "self_deaf":
                    isSelfDeafened = v as! Bool
                case "self_mute":
                    isSelfMuted = v as! Bool
                case "self_stream":
                    isStreaming = Conversions.optionalBooltoBool(v)
                case "self_video":
                    isCameraEnabled = v as! Bool
                case "suppress":
                    isSuppressed = v as! Bool
                case "request_to_speak_timestamp":
                    let requestDate = v as? String
                    requestedToSpeakAt = requestDate != nil ? Conversions.stringDateToDate(iso8601: requestDate!) : nil
                default:
                    break
                }
            }
        }
    }
}

/// Represents a thread.
public class ThreadChannel : GuildChannelMessageable, Hashable {

    /// The ID of the thread.
    public let id: Snowflake
    
    /// The thread type.
    public let type: ChannelType

    /// The channel this thread belongs to.
    public var channel: GuildChannel { guild.getChannel(parentChannelId)! }
    
    /// Name of the thread.
    public internal(set) var name: String
    
    /// The current value set for slowmode.
    public internal(set) var slowmode: Int

    /// Amount of members in the thread.
    public internal(set) var memberCount: Int

    /// The amount of messages in the thread.
    public internal(set) var messageCount: Int
    
    /// Permission overwrites for the channel. Will always be empty for a thread channel.
    public let overwrites = [PermissionOverwrites]()
    
    /// The ID of the last message sent in the thread.
    public internal(set) var lastMessageId: Snowflake?
    
    // docs set in `GuildChannel`
    public var categoryId: Snowflake? { channel.categoryId }
    
    /// The tags applied to a ``ForumChannel`` thread. If the thread does not belong to a forum, this will always be empty.
    public var appliedTags: [ForumChannel.Tag] {
        let parentChannel = guild.getChannel(parentChannelId)!
        if parentChannel.type == .guildForum {
            let forumChannel = parentChannel as! ForumChannel
            var includedTags = [ForumChannel.Tag]()
            
            for tagId in appliedTagsIds {
                if let match = forumChannel.tags.first(where: { $0.id == tagId }) { includedTags.append(match) }
            }
            return includedTags
        } else {
            return []
        }
    }
    private var appliedTagsIds = [Snowflake]()

    // --------- The below properties are apart of the thread metadata ---------
    
    /// Whether the thread is archived (closed).
    public internal(set) var isArchived: Bool
    
    /// When to automatically archive (close) the thread.
    public internal(set) var autoArchiveDuration: ArchiveDuration
    
    /// Timestamp when the thread's archive status was last changed.
    public internal(set) var archiveTimestamp: Date
    
    /// Whether the thread is locked.
    public internal(set) var isLocked: Bool
    
    /// Timestamp when the thread was created. Only available for threads created after January 9, 2022.
    public let createdAt: Date?

    // -------------------------------------------------------------------------
    
    // ---------- API Separated ----------
    
    /// The ID of the guild the channel belongs to.
    public let guildId: Snowflake
    
    // -----------------------------------
    
    // Hashable
    public static func == (lhs: ThreadChannel, rhs: ThreadChannel) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Your bot instance.
    public weak private(set) var bot: Bot?
    
    let parentChannelId: Snowflake

    init(bot: Bot, threadData: JSON, guildId: Snowflake) {
        self.bot = bot
        self.guildId = guildId
        id = Conversions.snowflakeToUInt(threadData["id"])
        type = ChannelType(rawValue: threadData["type"] as! Int)!
        parentChannelId = Conversions.snowflakeToUInt(threadData["parent_id"])
        name = threadData["name"] as! String
        slowmode = threadData["rate_limit_per_user"] as! Int
        memberCount = threadData["member_count"] as! Int
        messageCount = threadData["message_count"] as! Int
        
        if let tagIdStrs = threadData["applied_tags"] as? [String] {
            var tagIds = [Snowflake]()
            for tagIdStr in tagIdStrs {
                tagIds.append(Conversions.snowflakeToUInt(tagIdStr))
            }
            appliedTagsIds = tagIds
        }

        // Metadata
        let metadata = threadData["thread_metadata"] as! JSON
        isArchived = metadata["archived"] as! Bool
        autoArchiveDuration = ArchiveDuration(rawValue: metadata["auto_archive_duration"] as! Int)!
        archiveTimestamp = Conversions.stringDateToDate(iso8601: metadata["archive_timestamp"] as! String)!
        isLocked = metadata["locked"] as! Bool
        createdAt = metadata["create_timestamp"] as? String == nil ? nil : Conversions.stringDateToDate(iso8601: metadata["create_timestamp"] as! String)
    }
    
    /// Archive (close) the thread.
    public func archive() async throws {
        try await edit(.archived(true))
    }
    
    /// Add a member to the thread,
    /// - Parameter member: The member to add.
    public func addMember(_ member: Member) async throws {
        _ = try await bot!.http.addThreadMember(threadId: id, userId: member.id)
    }
    
    /// Edit the thread channel.
    /// - Parameters:
    ///   - edits: The enum containing all values to be updated or removed for the thread channel.
    ///   - reason: The reason for editing the thread channel. This shows up in the guilds audit log.
    /// - Returns: The updated thread.
    @discardableResult
    public func edit(_ edits: Edit..., reason: String? = nil) async throws -> ThreadChannel {
        guard !edits.isEmpty else { return self }
        
        var payload = JSON()
        
        for edit in edits {
            switch edit {
            case .name(let name):
                payload["name"] = name
            case .archived(let archived):
                payload["archived"] = archived
            case .autoArchiveDuration(let autoArchiveDuration):
                payload["auto_archive_duration"] = autoArchiveDuration.rawValue
            case .locked(let locked):
                payload["locked"] = locked
            case .invitable(let invitable):
                payload["invitable"] = invitable
            case .slowmode(let slowmode):
                payload["rate_limit_per_user"] = nullable(slowmode)
            case .pinned(let pinned):
                payload["flags"] = pinned ? ForumChannel.Flag.pinned.rawValue : 0
            case .appliedTags(let tags):
                payload["applied_tags"] = tags.map({ $0.id })
            }
        }
        return try await bot!.http.modifyChannel(channelId: id, guildId: guildId, json: payload, reason: reason) as! ThreadChannel
    }
    
    /// Remove a member from the thread,
    /// - Parameter member: The member to remove.
    public func removeMember(_ member: Member) async throws {
        _ = try await bot!.http.removeThreadMember(threadId: id, userId: member.id)
    }
    
    /// Join a non-archived thread.
    public func join() async throws {
        _ =  try await bot!.http.joinThread(threadId: id)
    }
    
    /// Leave a non-archived thread.
    public func leave() async throws {
        _ =  try await bot!.http.leaveThread(threadId: id)
    }
    
    /// Lock the thread.
    public func lock() async throws {
        try await edit(.locked(true))
    }
    
    /// Get the messages pinned to the channel.
    /// - Returns: The messages pinned to the channel.
    public func pins() async throws -> [Message] {
        return try await bot!.http.getPinnedMessages(channelId: id)
    }
    
    /// Get all members in the thread.
    /// - Returns: All members in the thread.
    /// - Note: This method  is restricted according to whether the guild members Privileged Intent is enabled for your application.
    public func members() async throws -> [ThreadMember] {
        return try await bot!.http.getThreadMembers(threadId: id)
    }
    
    /// Request a member in the thread.
    /// - Parameter id: The ID of the member.
    /// - Returns: The requested member matching the given ID.
    public func requestMember(_ id: Snowflake) async throws -> ThreadMember {
        return try await bot!.http.getThreadMember(threadId: self.id, userId: id)
    }
}

extension ThreadChannel {
    
    /// Represents the values that can be edited in a ``ThreadChannel``.
    public enum Edit {
        
        /// The channels name.
        case name(String)

        /// Whether the thread is archived (closed).
        case archived(Bool)

        /// The thread will stop showing in the channel list after x amount of minutes of inactivity.
        case autoArchiveDuration(ThreadChannel.ArchiveDuration)

        /// Whether the thread is locked; when a thread is locked.
        case locked(Bool)

        /// Whether non-moderators can add other non-moderators to a thread; only available on private threads.
        case invitable(Bool)

        /// Amount of seconds a user has to wait before sending another message (0-21600). Can be `nil` (or 0) to remove slowmode.
        case slowmode(Int?)

        /// Whether the thread is pinned. This is only valid for ``ForumChannel`` threads.
        case pinned(Bool)

        /// The tags that should be applied to the thread; max 5. Ony valud for ``ForumChannel`` threads. Use an empty array to remove all applied tags.
        case appliedTags([ForumChannel.Tag])
    }
    
    /// Represents a member in a thread.
    public struct ThreadMember {

        /// The ID of the thread.
        public let id: Snowflake?

        /// The ID of the user.
        public let userId: Snowflake?

        /// The time the current user last joined the thread.
        public let joinedAt: Date

        init(threadMemberData: JSON) {
            id = Conversions.snowflakeToUInt(threadMemberData["id"])
            userId = Conversions.snowflakeToUInt(threadMemberData["user_id"])
            joinedAt = Conversions.stringDateToDate(iso8601: threadMemberData["join_timestamp"] as! String)!
        }
    }
    
    /// Represents a threads archive duration.
    public enum ArchiveDuration : Int {
        case oneHour = 60
        case twentyfourHours = 1440
        case threeDays = 4320
        case sevenDays = 10080
    }
}

/// Represents a stage channel.
public class StageChannel : VoiceChannel {
    
    init(bot: Bot, scData: JSON, guildId: Snowflake) {
        super.init(bot: bot, vcData: scData, guildId: guildId)
    }
    
    /// Creates a stage instance.
    /// - Parameters:
    ///   - topic: The topic of the Stage instance (1-120 characters).
    ///   - privacyLevel: The privacy level of the Stage instance.
    ///   - startNotification: Notify @everyone that a Stage instance has started.
    ///   - reason: The reason for creating the instance. This shows up in the guilds audit log.
    /// - Returns: The newly created instance.
    public func createInstance(topic: String, privacyLevel: StageInstance.PrivacyLevel = .guildOnly, startNotification: Bool = false, reason: String? = nil) async throws -> StageInstance {
        try await bot!.http.createStageInstance(stageChannelId: id, topic: topic, privacyLevel: privacyLevel, startNotification: startNotification, reason: reason)
    }
    
    /// Edit the stage channel.
    /// - Parameters:
    ///   - edits: The enum containing all values to be updated or removed for the stage channel.
    ///   - reason: The reason for editing the stage channel. This shows up in the guilds audit log.
    /// - Returns: The updated stage channel.
    @discardableResult
    public func edit(_ edits: Edit..., reason: String? = nil) async throws -> StageChannel {
        guard !edits.isEmpty else { return self }

        var payload = JSON()

        for edit in edits {
            switch edit {
            case .bitrate(let bitrate):
                payload["bitrate"] = bitrate
            case .category(let category):
                payload["parent_id"] = nullable(category?.id)
            case .name(let name):
                payload["name"] = name
            case .position(let position):
                payload["position"] = nullable(position)
            case .region(let region):
                payload["rtc_region"] = region == .automatic ? NIL : region.rawValue
            case .overwrites(let permOverwrites):
                payload["permission_overwrites"] = nullable(permOverwrites?.map({ $0.convert() }))
            }
        }
        return try await bot!.http.modifyChannel(channelId: id, guildId: guildId, json: payload, reason: reason) as! StageChannel
    }
    
    /// Requests the Stage instance.
    /// - Returns: The stage instance for the stage channel if it exists.
    public func requestInstance() async throws -> StageInstance {
        try await bot!.http.getStageInstance(channelId: id)
    }
}

extension StageChannel {
    
    /// Represents the values that can be edited in a ``StageChannel``.
    public enum Edit {
        
        /// The bitrate (in bits) of the stage channel. Maximum of 64000.
        case bitrate(Int)
        
        /// The category the channel belongs to. Can be `nil` for no category.
        case category(CategoryChannel?)
        
        /// The channel name.
        case name(String)
        
        /// Sorting position of the channel. Can be `nil` for automatic sorting.
        case position(Int?)
        
        /// Voice region ID for the stage channel.
        case region(VoiceChannel.RtcRegion)
        
        /// Permission overwrites for members and role.
        case overwrites([PermissionOverwrites]?)
    }
}

/// Represents a live stage.
public struct StageInstance : Hashable {

    /// The ID of this stage instance.
    public let id: Snowflake
    
    /// The guild of the associated stage channel.
    public var guild: Guild { bot!.getGuild(guildId)! }
    private let guildId: Snowflake

    /// The ID of the associated stage channel.
    public let channelId: Snowflake

    /// The topic of the stage instance.
    public internal(set) var topic: String

    /// The privacy level of the stage instance.
    public internal(set) var privacyLevel: StageInstance.PrivacyLevel

    /// The ID of the scheduled event for this stage instance.
    public let guildScheduledEventId: Snowflake?

    /// Your bot instance.
    public weak private(set) var bot: Bot?

    // ------------- API Separated -------------
    
    /// Mention the channel.
    public let mention: String
    
    // -----------------------------------------
    
    // Hashable
    public static func == (lhs: StageInstance, rhs: StageInstance) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(bot: Bot, stageInstanceData: JSON) {
        self.bot = bot
        id = Conversions.snowflakeToUInt(stageInstanceData["id"])
        
        guildId = Conversions.snowflakeToUInt(stageInstanceData["guild_id"])

        channelId = Conversions.snowflakeToUInt(stageInstanceData["channel_id"])
        topic = stageInstanceData["topic"] as! String
        privacyLevel = PrivacyLevel(rawValue: stageInstanceData["privacy_level"] as! Int)!
        guildScheduledEventId = Conversions.snowflakeToOptionalUInt(stageInstanceData["guild_scheduled_event_id"])

        mention = Markdown.mentionChannel(id: id)
    }
    
    /// Edit the stage instance.
    /// - Parameters:
    ///   - topic: The stage instance topic.
    ///   - reason: The reason for editing the stage instance. This shows up in the guilds audit log.
    /// - Returns: The updated stage instance.
    public func edit(topic: String, reason: String? = nil) async throws -> StageInstance {
        try await bot!.http.modifyStageInstance(stageChannelId: channelId, topic: topic, reason: reason)
    }
    
 
    /// Delete the stage instance.
    /// - Parameter reason: The reason for deleting the stage.
    public func delete(reason: String? = nil) async throws {
        try await bot!.http.deleteStageInstance(channelId: channelId, reason: reason)
    }
}

extension StageInstance {
    
    /// Represents the stage instance privacy level.
    public enum PrivacyLevel : Int {
        
        // "public" is deprecated
        
        /// The Stage instance is visible to only guild members.
        case guildOnly = 2
    }
}
