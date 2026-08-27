import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

// MARK: - Persistence

public struct PyzogramSettings: Equatable {
    public var ghostMode: Bool
    public var showDeletedMessages: Bool
    public var hideTyping: Bool

    public static var `default`: PyzogramSettings {
        return PyzogramSettings(ghostMode: false, showDeletedMessages: false, hideTyping: false)
    }

    private static let ghostModeKey = "pyzogram.ghostMode"
    private static let showDeletedMessagesKey = "pyzogram.showDeletedMessages"
    private static let hideTypingKey = "pyzogram.hideTyping"

    public static func load() -> PyzogramSettings {
        let defaults = UserDefaults.standard
        return PyzogramSettings(
            ghostMode: defaults.object(forKey: ghostModeKey) as? Bool ?? false,
            showDeletedMessages: defaults.object(forKey: showDeletedMessagesKey) as? Bool ?? false,
            hideTyping: defaults.object(forKey: hideTypingKey) as? Bool ?? false
        )
    }

    public func save() {
        let defaults = UserDefaults.standard
        defaults.set(self.ghostMode, forKey: PyzogramSettings.ghostModeKey)
        defaults.set(self.showDeletedMessages, forKey: PyzogramSettings.showDeletedMessagesKey)
        defaults.set(self.hideTyping, forKey: PyzogramSettings.hideTypingKey)
        defaults.synchronize()
    }
}

private let pyzogramSettingsPromise = Promise<PyzogramSettings>(PyzogramSettings.load())

// MARK: - Settings list

private final class PyzogramSettingsArguments {
    let setGhostMode: (Bool) -> Void
    let setShowDeletedMessages: (Bool) -> Void
    let setHideTyping: (Bool) -> Void
    let openAuthor: () -> Void

    init(setGhostMode: @escaping (Bool) -> Void, setShowDeletedMessages: @escaping (Bool) -> Void, setHideTyping: @escaping (Bool) -> Void, openAuthor: @escaping () -> Void) {
        self.setGhostMode = setGhostMode
        self.setShowDeletedMessages = setShowDeletedMessages
        self.setHideTyping = setHideTyping
        self.openAuthor = openAuthor
    }
}

private enum PyzogramSection: Int32 {
    case main
    case about
}

private enum PyzogramEntry: ItemListNodeEntry {
    case header(PresentationTheme, String)
    case ghostMode(PresentationTheme, Bool)
    case hideTyping(PresentationTheme, Bool)
    case showDeletedMessages(PresentationTheme, Bool)
    case info(PresentationTheme, String)
    case author(PresentationTheme, String, String)

    var section: ItemListSectionId {
        switch self {
        case .header, .ghostMode, .hideTyping, .showDeletedMessages, .info:
            return PyzogramSection.main.rawValue
        case .author:
            return PyzogramSection.about.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case .ghostMode:
            return 1
        case .hideTyping:
            return 2
        case .showDeletedMessages:
            return 3
        case .info:
            return 4
        case .author:
            return 100
        }
    }

    static func ==(lhs: PyzogramEntry, rhs: PyzogramEntry) -> Bool {
        switch lhs {
        case let .header(lhsTheme, lhsText):
            if case let .header(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
        case let .ghostMode(lhsTheme, lhsValue):
            if case let .ghostMode(rhsTheme, rhsValue) = rhs, lhsTheme === rhsTheme, lhsValue == rhsValue {
                return true
            } else {
                return false
            }
        case let .hideTyping(lhsTheme, lhsValue):
            if case let .hideTyping(rhsTheme, rhsValue) = rhs, lhsTheme === rhsTheme, lhsValue == rhsValue {
                return true
            } else {
                return false
            }
        case let .showDeletedMessages(lhsTheme, lhsValue):
            if case let .showDeletedMessages(rhsTheme, rhsValue) = rhs, lhsTheme === rhsTheme, lhsValue == rhsValue {
                return true
            } else {
                return false
            }
        case let .info(lhsTheme, lhsText):
            if case let .info(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
        case let .author(lhsTheme, lhsTitle, lhsLabel):
            if case let .author(rhsTheme, rhsTitle, rhsLabel) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsLabel == rhsLabel {
                return true
            } else {
                return false
            }
        }
    }

    static func <(lhs: PyzogramEntry, rhs: PyzogramEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PyzogramSettingsArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .ghostMode(_, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: "Режим призрака",
                text: "Скрывает статус «в сети», набор текста и отметки о прочтении",
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.setGhostMode(newValue)
                }
            )
        case let .hideTyping(_, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: "Скрывать набор текста",
                text: "Собеседники не видят, что вы печатаете",
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.setHideTyping(newValue)
                }
            )
        case let .showDeletedMessages(_, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: "Показывать удалённые сообщения",
                text: "Сохраняет текст сообщений, удалённых собеседником",
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.setShowDeletedMessages(newValue)
                }
            )
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .author(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openAuthor()
                }
            )
        }
    }
}

private func pyzogramControllerEntries(presentationData: PresentationData, settings: PyzogramSettings) -> [PyzogramEntry] {
    var entries: [PyzogramEntry] = []

    entries.append(.header(presentationData.theme, "Pyzogram"))
    entries.append(.ghostMode(presentationData.theme, settings.ghostMode))
    entries.append(.hideTyping(presentationData.theme, settings.hideTyping))
    entries.append(.showDeletedMessages(presentationData.theme, settings.showDeletedMessages))
    entries.append(.info(presentationData.theme, "Эти функции работают поверх официального Telegram. Используйте на свой страх и риск."))

    entries.append(.author(presentationData.theme, "Автор", "@L1ngDev"))

    return entries
}

public func makePyzogramSettingsController(context: AccountContext) -> ViewController {
    let updateDisposable = MetaDisposable()

    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = PyzogramSettingsArguments(
        setGhostMode: { value in
            var settings = PyzogramSettings.load()
            settings.ghostMode = value
            settings.save()
            pyzogramSettingsPromise.set(.single(settings))
            updateDisposable.set(applyGhostModeInteractively(value).start())
        },
        setShowDeletedMessages: { value in
            var settings = PyzogramSettings.load()
            settings.showDeletedMessages = value
            settings.save()
            pyzogramSettingsPromise.set(.single(settings))
        },
        setHideTyping: { value in
            var settings = PyzogramSettings.load()
            settings.hideTyping = value
            settings.save()
            pyzogramSettingsPromise.set(.single(settings))
        },
        openAuthor: {
            let controller = makePyzogramAuthorController(context: context)
            pushControllerImpl?(controller)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, pyzogramSettingsPromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Pyzogram"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pyzogramControllerEntries(presentationData: presentationData, settings: settings),
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}

// MARK: - Author screen

private final class AuthorArguments {
    let openGitHub: () -> Void
    let openTelegram: () -> Void

    init(openGitHub: @escaping () -> Void, openTelegram: @escaping () -> Void) {
        self.openGitHub = openGitHub
        self.openTelegram = openTelegram
    }
}

private enum AuthorEntry: ItemListNodeEntry {
    case header(PresentationTheme, String)
    case github(PresentationTheme, String, String)
    case telegram(PresentationTheme, String, String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case .github:
            return 1
        case .telegram:
            return 2
        }
    }

    static func ==(lhs: AuthorEntry, rhs: AuthorEntry) -> Bool {
        switch lhs {
        case let .header(lhsTheme, lhsText):
            if case let .header(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
        case let .github(lhsTheme, lhsTitle, lhsLabel):
            if case let .github(rhsTheme, rhsTitle, rhsLabel) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsLabel == rhsLabel {
                return true
            } else {
                return false
            }
        case let .telegram(lhsTheme, lhsTitle, lhsLabel):
            if case let .telegram(rhsTheme, rhsTitle, rhsLabel) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsLabel == rhsLabel {
                return true
            } else {
                return false
            }
        }
    }

    static func <(lhs: AuthorEntry, rhs: AuthorEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AuthorArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .github(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openGitHub()
                }
            )
        case let .telegram(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openTelegram()
                }
            )
        }
    }
}

public func makePyzogramAuthorController(context: AccountContext) -> ViewController {
    let openUrl: (String) -> Void = { urlString in
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    let arguments = AuthorArguments(
        openGitHub: {
            openUrl("https://github.com/L1ngDev")
        },
        openTelegram: {
            openUrl("https://t.me/logountw")
        }
    )

    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Автор"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )

        var entries: [AuthorEntry] = []
        entries.append(.header(presentationData.theme, "Pyzogram"))
        entries.append(.github(presentationData.theme, "GitHub", "@L1ngDev"))
        entries.append(.telegram(presentationData.theme, "Telegram", "@logountw"))

        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    return controller
}

// MARK: - Behavior hooks (best-effort)

private func applyGhostModeInteractively(_ enabled: Bool) -> Signal<Void, NoError> {
    return .complete()
}
