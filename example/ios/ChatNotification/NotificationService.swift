import UserNotifications
import Intents

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        if(bestAttemptContent == nil) {
            return;
        }

        let payload: [AnyHashable : Any] = bestAttemptContent!.userInfo
        let type: String? = payload["type"] as? String

        if(type == "chat") {
            _handleChatMessage(payload: payload)

            return;
        }

        if let bestAttemptContent =  bestAttemptContent {
            let imageUrl: String? = payload["image_url"] as? String
            
            var attachments: [UNNotificationAttachment] = [];

            if let imageUrl = imageUrl, !imageUrl.isEmpty {
                let url = URL(string: imageUrl)
                let fileName = url!.lastPathComponent

                let imageData = try? Data(contentsOf: url!)

                if(imageData != nil) {
                    let attachment = createNotificationAttachment(identifier: "media", fileName: fileName, data: imageData!, options: nil)

                    if attachment != nil {
                        attachments.append(attachment!)
                    }
                }
            }
            
            bestAttemptContent.attachments = attachments
            
            contentHandler(bestAttemptContent)
        }
    }

    func _handleChatMessage(payload: [AnyHashable : Any]) {
        guard let content = bestAttemptContent else {
            return
        }

        guard let contentHandler = contentHandler else {
            return
        }

        var _avatar:  INImage? = nil
        var _groupAvatar:  INImage? = nil
        
        let groupName: String? = payload["group_name"] as? String
        let groupId: String? = payload["group_id"] as? String
        let senderId: String = payload["sender_id"] as? String ?? ""
        var senderName: String = payload["sender_name"] as? String ?? ""
        var message: String = payload["message"] as? String ?? ""
        let avatar: String? = payload["avatar"] as? String
        let groupAvatar: String? = payload["group_avatar"] as? String
        let imageUrl: String? = payload["image_url"] as? String

        if let avatar = avatar, let senderAvatarUrl = URL(string: avatar) {
            let senderAvatarFileName = senderAvatarUrl.lastPathComponent

            if let senderAvatarImageData = try? Data(contentsOf: senderAvatarUrl),
                let senderAvatarImageFileUrl = downloadAttachment(data: senderAvatarImageData, fileName: senderAvatarFileName),
                let senderAvatarImageFileData = try? Data(contentsOf: senderAvatarImageFileUrl) {

                _avatar = INImage(imageData: senderAvatarImageFileData)
            }
        }
        
        if let groupAvatar = groupAvatar, let url = URL(string: groupAvatar) {
            let fileName = url.lastPathComponent

            if let imageData = try? Data(contentsOf: url),
                let imageFileUrl = downloadAttachment(data: imageData, fileName: fileName),
                let imageFileData = try? Data(contentsOf: imageFileUrl) {

                _groupAvatar = INImage(imageData: imageFileData)
            }
        }
        
        var attachments: [UNNotificationAttachment] = [];

        if let imageUrl = imageUrl, !imageUrl.isEmpty {
            let url = URL(string: imageUrl)
            let fileName = url!.lastPathComponent

            let imageData = try? Data(contentsOf: url!)

            if(imageData != nil) {
                let attachment = createNotificationAttachment(identifier: "media", fileName: fileName, data: imageData!, options: nil)

                if attachment != nil {
                    attachments.append(attachment!)
                }
            }
        }

        content.attachments = attachments
        
        var personNameComponents = PersonNameComponents()
        personNameComponents.nickname = senderName
        
        if groupId != nil {
            message = senderName + ": " + message
            senderName = groupName!
            _avatar = _groupAvatar
        }
        
        bestAttemptContent?.body = message;

        let senderPerson = INPerson(
                                    personHandle: INPersonHandle(
                                                    value: senderId,
                                                    type: .unknown
                                                ),
                                    nameComponents: personNameComponents,
                                    displayName: senderName,
                                    image: _avatar,
                                    contactIdentifier: nil,
                                    customIdentifier: nil,
                                    isMe: false,
                                    suggestionType: .none
                                )

        let selfPerson = INPerson(
                                    personHandle: INPersonHandle(
                                                    value: "00000000-0000-0000-0000-000000000000-12345678",
                                                    type: .unknown
                                                ),
                                    nameComponents: nil,
                                    displayName: nil,
                                    image: nil,
                                    contactIdentifier: nil,
                                    customIdentifier: nil,
                                    isMe: true,
                                    suggestionType: .none
                                )
        
        
        let incomingMessagingIntent = INSendMessageIntent(
                                            recipients: [selfPerson],
                                            outgoingMessageType: .outgoingMessageText,
                                            content: message,
                                            speakableGroupName: nil,
                                            conversationIdentifier: groupId,
                                            serviceName: nil,
                                            sender: senderPerson,
                                            attachments: []
                                    )

        incomingMessagingIntent.setImage(_avatar, forParameterNamed: \.sender)

        let interaction = INInteraction(intent: incomingMessagingIntent, response: nil)

        interaction.direction = .incoming

        do {
            bestAttemptContent = try content.updating(from: incomingMessagingIntent) as? UNMutableNotificationContent
            contentHandler(bestAttemptContent!)
        } catch let error {
            print("error \(error)")
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}

func createNotificationAttachment(identifier: String, fileName: String, data: Data, options: [NSObject : AnyObject]?) -> UNNotificationAttachment? {
    do {
       if let fileURL: URL = downloadAttachment(data: data, fileName: fileName) {
            let attachment: UNNotificationAttachment = try UNNotificationAttachment.init(identifier: identifier, url: fileURL, options: options)

            return attachment
        }

        return nil
    } catch let error {
        print("error \(error)")
    }

    return nil
}

func downloadAttachment(data: Data, fileName: String) -> URL? {
    let fileManager = FileManager.default
    let tmpSubFolderName = ProcessInfo.processInfo.globallyUniqueString
    let tmpSubFolderURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(tmpSubFolderName, isDirectory: true)

    do {
        try fileManager.createDirectory(at: tmpSubFolderURL, withIntermediateDirectories: true, attributes: nil)
        let fileURL: URL = tmpSubFolderURL.appendingPathComponent(fileName)
        try data.write(to: fileURL)

        return fileURL
    } catch let error {
        print("error \(error)")
    }

    return nil
}