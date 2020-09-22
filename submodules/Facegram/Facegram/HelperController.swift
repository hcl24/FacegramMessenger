import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import SyncCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class HelperControllerArguments {
    let openLanguage: () -> Void
    

    init(openLanguage: @escaping () -> Void) {
        self.openLanguage = openLanguage
    }
}

private enum HelperSection: Int32 {
    case language
}

private enum HelperEntry: ItemListNodeEntry {
    case language(PresentationTheme, String)
    
    var section: ItemListSectionId {
        switch self {
            case .language:
                return HelperSection.language.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
            case .language:
                return 0
        }
    }
    
    static func ==(lhs: HelperEntry, rhs: HelperEntry) -> Bool {
        switch lhs {
            case let .language(lhsTheme, lhsText):
                if case let .language(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: HelperEntry, rhs: HelperEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! HelperControllerArguments
        switch self {
            case let .language(theme, text):
                return ItemListDisclosureItem(presentationData: presentationData, title: text, label: "", sectionId: self.section, style: .blocks, action: {
                    arguments.openLanguage()
                })
        }
    }
}

private func helperControllerEntries(presentationData: PresentationData) -> [HelperEntry] {
    var entries: [HelperEntry] = []
    
    entries.append(.language(presentationData.theme, presentationData.strings.Settings_AppLanguage))
    
    return entries
}

func helperController(context: AccountContext) -> ViewController {
    
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    
    let actionsDisposable = DisposableSet()
    
    let arguments = HelperControllerArguments(openLanguage: {
        pushControllerImpl?(LanguageController(context: context))
    })

    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
       
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(presentationData.strings.UserInfo_BotHelp), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: helperControllerEntries(presentationData: presentationData), style: .blocks, ensureVisibleItemTag: nil, emptyStateItem: nil, animateChanges: false)
        
        return (controllerState, (listState, arguments))
    } |> afterDisposed {
        actionsDisposable.dispose()
    }
    
    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        if let controller = controller {
            (controller.navigationController as? NavigationController)?.pushViewController(c)
        }
    }
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }

    return controller
}

