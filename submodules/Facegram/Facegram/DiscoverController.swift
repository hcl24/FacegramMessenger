import Foundation
import UIKit
import Display
import AccountContext
import TelegramPresentationData
import SyncCore
import ItemListUI
import Postbox
import SwiftSignalKit
import PhoneNumberFormat
import DeviceAccess
import TelegramPermissions
import TelegramPermissionsUI
import TelegramUIPreferences
import TelegramCore
import TelegramNotices
import SearchUI
import ItemListAvatarAndNameInfoItem
import ContextUI
import AsyncDisplayKit
import AvatarNode
import PresentationDataUtils
import AuthTransferUI

private final class DiscoverItemArguments {
    let sharedContext: SharedAccountContext
    let openPeopleNearby: () -> Void
    let openScan: () -> Void
    let pushController: (ViewController) -> Void
    let openTools: () -> Void
   
    init(
        sharedContext: SharedAccountContext,
        openPeopleNearby: @escaping () -> Void,
        openScan: @escaping () -> Void,
        pushController: @escaping (ViewController) -> Void,
        openTools: @escaping () -> Void
    ) {
        self.sharedContext = sharedContext
        self.openPeopleNearby = openPeopleNearby
        self.openScan = openScan
        self.pushController = pushController
        self.openTools = openTools
    }
}

private enum DiscoverSection: Int32 {
    case devices
    case peopleNearby
}

private indirect enum DiscoverEntry: ItemListNodeEntry {
    case devicesTips(PresentationTheme, String)
    case devices(PresentationTheme, UIImage?, String)
    case peopleNearby(PresentationTheme, UIImage?, String)
    case tools(PresentationTheme, UIImage?, String)
    
    var section: ItemListSectionId {
        switch self {
        case .devicesTips, .devices:
            return DiscoverSection.devices.rawValue
        case .peopleNearby, .tools:
            return DiscoverSection.peopleNearby.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
        case .devicesTips:
            return 1000
        case .devices:
            return 1001
        case .peopleNearby:
            return 1002
        case .tools:
            return 1003
        }
    }
    
    static func ==(lhs: DiscoverEntry, rhs: DiscoverEntry) -> Bool {
        switch lhs {
            case let .devicesTips(lhsTheme, lhsText):
            if case let .devicesTips(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            } else {
                return false
            }
            case let .devices(lhsTheme, lhsImage, lhsText):
            if case let .devices(rhsTheme, rhsImage, rhsText) = rhs, lhsTheme === rhsTheme, lhsImage === rhsImage, lhsText == rhsText {
                return true
            } else {
                return false
            }
            case let .peopleNearby(lhsTheme, lhsImage, lhsText):
                if case let .peopleNearby(rhsTheme, rhsImage, rhsText) = rhs, lhsTheme === rhsTheme, lhsImage === rhsImage, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .tools(lhsTheme, lhsImage, lhsText):
                if case let .tools(rhsTheme, rhsImage, rhsText) = rhs, lhsTheme === rhsTheme, lhsImage === rhsImage, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: DiscoverEntry, rhs: DiscoverEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DiscoverItemArguments
        switch self {
            case let .devicesTips(theme, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: ItemListSectionId(self.section), style: .blocks)
            case let .devices(theme, image, text):
                return ItemListDisclosureItem(presentationData: presentationData, icon: image, title: text, label: "", sectionId: ItemListSectionId(self.section), style: .blocks, action: {
                    arguments.openScan()
                }, clearHighlightAutomatically: false)
            case let .peopleNearby(theme, image, text):
                return ItemListDisclosureItem(presentationData: presentationData, icon: image, title: text, label: "", sectionId: ItemListSectionId(self.section), style: .blocks, action: {
                    arguments.openPeopleNearby()
                }, clearHighlightAutomatically: false)
            case let .tools(theme, image, text):
                return ItemListDisclosureItem(presentationData: presentationData, icon: image, title: text, label: "", sectionId: ItemListSectionId(self.section), style: .blocks, action: {
                    arguments.openTools()
                }, clearHighlightAutomatically: false)
        }
    }
}

private func discoverEntries(account: Account, presentationData: PresentationData) -> [DiscoverEntry] {
    var entries: [DiscoverEntry] = []
    entries.append(.devicesTips(presentationData.theme, presentationData.strings.AuthSessions_AddDeviceIntro_Text3))
    entries.append(.devices(presentationData.theme, PresentationResourcesDiscover.devices, presentationData.strings.AuthSessions_AddDeviceIntro_Title))
    entries.append(.peopleNearby(presentationData.theme, PresentationResourcesDiscover.peopleNearby, presentationData.strings.PeopleNearby_Title))
    entries.append(.tools(presentationData.theme, PresentationResourcesDiscover.tools, presentationData.strings.UserInfo_BotHelp))
    
    return entries
}

public protocol DiscoverController: class {
    func updateContext(context: AccountContext)
}

private final class DiscoverControllerImpl: ItemListController, DiscoverController {
    let sharedContext: SharedAccountContext
    let contextValue: Promise<AccountContext>
    
    override var navigationBarRequiresEntireLayoutUpdate: Bool {
        return false
    }

    init(currentContext: AccountContext, contextValue: Promise<AccountContext>, state: Signal<(ItemListControllerState, (ItemListNodeState, Any)), NoError>, tabBarItem: Signal<ItemListControllerTabBarItem, NoError>?) {
        self.sharedContext = currentContext.sharedContext
        self.contextValue = contextValue
        let presentationData = currentContext.sharedContext.currentPresentationData.with { $0 }
        
        self.contextValue.set(.single(currentContext))
        
        let updatedPresentationData = self.contextValue.get()
        |> mapToSignal { context -> Signal<PresentationData, NoError> in
            return context.sharedContext.presentationData
        }
        
        super.init(presentationData: ItemListPresentationData(presentationData), updatedPresentationData: updatedPresentationData |> map(ItemListPresentationData.init(_:)), state: state, tabBarItem: tabBarItem)
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        
    }
    
    func updateContext(context: AccountContext) {
        //self.contextValue.set(.single(context))
    }
}

public func discoverController(context: AccountContext) -> DiscoverController & ViewController {
    
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController, Any?) -> Void)?
    var presentInGlobalOverlayImpl: ((ViewController, Any?) -> Void)?
    var dismissInputImpl: (() -> Void)?
    var setDisplayNavigationBarImpl: ((Bool) -> Void)?
    var getNavigationControllerImpl: (() -> NavigationController?)?
    
    let actionsDisposable = DisposableSet()
    
    var openPeopleNearbyImpl: (() -> Void)?
    
    let contextValue = Promise<AccountContext>()
    
    let enableQRLogin = Promise<Bool>()
    
    let activeSessionsContextAndCountSignal = contextValue.get()
    |> deliverOnMainQueue
    |> mapToSignal { context -> Signal<(ActiveSessionsContext, Int, WebSessionsContext), NoError> in
        let activeSessionsContext = ActiveSessionsContext(account: context.account)
        let webSessionsContext = WebSessionsContext(account: context.account)
        let otherSessionCount = activeSessionsContext.state
        |> map { state -> Int in
            return state.sessions.filter({ !$0.isCurrent }).count
        }
        |> distinctUntilChanged
        return otherSessionCount
        |> map { value in
            return (activeSessionsContext, value, webSessionsContext)
        }
    }
    let activeSessionsContextAndCount = Promise<(ActiveSessionsContext, Int, WebSessionsContext)>()
    activeSessionsContextAndCount.set(activeSessionsContextAndCountSignal)
    
    let arguments = DiscoverItemArguments(sharedContext: context.sharedContext, openPeopleNearby: {
        openPeopleNearbyImpl?()
    }, openScan: {
        let _ = (contextValue.get()
        |> deliverOnMainQueue
        |> take(1)).start(next: { context in
            let _ = (combineLatest(queue: .mainQueue(),
                activeSessionsContextAndCount.get(),
                enableQRLogin.get()
            )
            |> take(1)).start(next: { activeSessionsContextAndCount, enableQRLogin in
                let (activeSessionsContext, count, webSessionsContext) = activeSessionsContextAndCount
                pushControllerImpl?(AuthDataTransferSplashScreen(context: context, activeSessionsContext: activeSessionsContext))
                /*
                if count == 0 && enableQRLogin {
                    pushControllerImpl?(AuthDataTransferSplashScreen(context: context, activeSessionsContext: activeSessionsContext))
                } else {
                    print("other things to do...")
                }
                */
            })
        })
    }, pushController: { controller in
        pushControllerImpl?(controller)
    }, openTools: {
        pushControllerImpl?(helperController(context: context))
    })
    
    let updatedPresentationData = contextValue.get()
    |> mapToSignal { context -> Signal<PresentationData, NoError> in
        return context.sharedContext.presentationData
    }
    
    let enableQRLoginSignal = contextValue.get()
    |> mapToSignal { context -> Signal<Bool, NoError> in
        return context.account.postbox.preferencesView(keys: [PreferencesKeys.appConfiguration])
        |> map { view -> Bool in
            guard let appConfiguration = view.values[PreferencesKeys.appConfiguration] as? AppConfiguration else {
                return false
            }
            guard let data = appConfiguration.data, let enableQR = data["qr_login_camera"] as? Bool, enableQR else {
                return false
            }
            return true
        }
        |> distinctUntilChanged
    }
    enableQRLogin.set(enableQRLoginSignal)
    
    let signal = combineLatest(queue: Queue.mainQueue(), contextValue.get(), updatedPresentationData)
    |> map { context, presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        /*
        let rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Edit), style: .regular, enabled: true, action: {
        })
        */
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Facegram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: discoverEntries(account: context.account, presentationData: presentationData), style: .blocks, searchItem: nil, initialScrollToItem: ListViewScrollToItem(index: 0, position: .top(-navigationBarSearchContentHeight), animated: false, curve: .Default(duration: 0.0), directionHint: .Up))
        
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        actionsDisposable.dispose()
    }
    
    let icon: UIImage?
    if useSpecialTabBarIcons() {
        icon = UIImage(bundleImageName: "Chat/Message/SecretMediaIcon")
    } else {
        icon = UIImage(bundleImageName: "Chat/Message/SecretMediaIcon")
    }
        
    let tabBarItem: Signal<ItemListControllerTabBarItem, NoError> = updatedPresentationData
    |> map { presentationData -> ItemListControllerTabBarItem in
        return ItemListControllerTabBarItem(title: "Facegram", image: icon, selectedImage: icon, tintImages: true, badgeValue: "")
    }
    
    let controller = DiscoverControllerImpl(currentContext: context, contextValue: contextValue, state: signal, tabBarItem: tabBarItem)
    pushControllerImpl = { [weak controller] value in
        (controller?.navigationController as? NavigationController)?.replaceAllButRootController(value, animated: true, animationOptions: [.removeOnMasterDetails])
    }
    presentControllerImpl = { [weak controller] value, arguments in
        controller?.present(value, in: .window(.root), with: arguments, blockInteraction: true)
    }
    presentInGlobalOverlayImpl = { [weak controller] value, arguments in
        controller?.presentInGlobalOverlay(value, with: arguments)
    }
    dismissInputImpl = { [weak controller] in
        controller?.view.window?.endEditing(true)
    }
    getNavigationControllerImpl = { [weak controller] in
        return (controller?.navigationController as? NavigationController)
    }

    openPeopleNearbyImpl = { [weak controller] in
        let _ = (DeviceAccess.authorizationStatus(subject: .location(.tracking))
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak controller] status in
            guard let strongSelf = controller else {
                return
            }
            let presentPeersNearby = {
                let peersNearbyController = context.sharedContext.makePeersNearbyController(context: context)
                peersNearbyController.navigationPresentation = .master
                pushControllerImpl?(peersNearbyController)
            }
            
            switch status {
                case .allowed:
                    presentPeersNearby()
                default:
                    let permissionController = PermissionController(context: context, splashScreen: false)
                    permissionController.setState(.permission(.nearbyLocation(status: PermissionRequestStatus(accessType: status))), animated: false)
                    permissionController.navigationPresentation = .master
                    permissionController.proceed = { result in
                        if result {
                            presentPeersNearby()
                        } else {
                            let _ = (permissionController.navigationController as? NavigationController)?.popViewController(animated: true)
                        }
                    }
                    pushControllerImpl?(permissionController)
            }
        })
    }
    
    controller.tabBarItemDebugTapAction = {
       
    }
    controller.didAppear = { _ in
        
    }
    controller.commitPreview = { previewController in

    }
    
    controller.contentOffsetChanged = { [weak controller] offset, inVoiceOver in
        if let controller = controller, let navigationBar = controller.navigationBar, let searchContentNode = navigationBar.contentNode as? NavigationBarSearchContentNode {
            var offset = offset
            if inVoiceOver {
                offset = .known(0.0)
            }
            searchContentNode.updateListVisibleContentOffset(offset)
        }
    }
    
    controller.contentScrollingEnded = { [weak controller] listNode in
        if let controller = controller, let navigationBar = controller.navigationBar, let searchContentNode = navigationBar.contentNode as? NavigationBarSearchContentNode {
            return fixNavigationSearchableListNodeScrolling(listNode, searchNode: searchContentNode)
        }
        return false
    }
    
    controller.willScrollToTop = { [weak controller] in
         if let controller = controller, let navigationBar = controller.navigationBar, let searchContentNode = navigationBar.contentNode as? NavigationBarSearchContentNode {
            searchContentNode.updateExpansionProgress(1.0, animated: true)
        }
    }
    
    controller.didDisappear = { [weak controller] _ in
        controller?.clearItemNodesHighlight(animated: true)
        setDisplayNavigationBarImpl?(true)
    }

    setDisplayNavigationBarImpl = { [weak controller] display in
        controller?.setDisplayNavigationBar(display, transition: .animated(duration: 0.5, curve: .spring))
    }
    
    return controller
}
