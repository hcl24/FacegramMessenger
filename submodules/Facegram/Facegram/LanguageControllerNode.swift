import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SyncCore
import SwiftSignalKit
import TelegramPresentationData
import MergeLists
import ItemListUI
import PresentationDataUtils
import AccountContext
import ShareController
import ActivityIndicator

private struct LanguageInfo {
    let title: String
    let subtitle: String
    let code: String
}

private enum LanguageListSection: ItemListSectionId {
    case language
}

private enum LanguageListEntryId: Hashable {
    case search
    case localization(String)
}

private enum LanguageListEntry: Comparable, Identifiable {
    case localization(index: Int, title: String, subtitle: String, code: String, selected: Bool, activity: Bool, revealed: Bool, editing: Bool)
    
    var section: ItemListSectionId {
        switch self {
        case .localization:
            return LanguageListSection.language.rawValue
        }
    }
    
    var stableId: Int {
        switch self {
        case let .localization(index, _, _, _, _, _, _, _):
            return 10000 + index
        }
    }
    
    private func index() -> Int {
        switch self {
            case let .localization(index, _, _, _, _, _, _, _):
                return index
        }
    }
    
    static func <(lhs: LanguageListEntry, rhs: LanguageListEntry) -> Bool {
       return lhs.index() < rhs.index()
    }
    
    func item(presentationData: PresentationData, selectLocalization: @escaping (String) -> Void, setItemWithRevealedOptions: @escaping (String?, String?) -> Void) -> ListViewItem {
        switch self {
            case let .localization(_, title, subtitle, code, selected, activity, revealed, editing):
                return LanguageListItem(presentationData: ItemListPresentationData(presentationData), id: code, title: title, subtitle: subtitle, checked: false, activity: false, sectionId: LanguageListSection.language.rawValue, alwaysPlain: true, action: {
                    selectLocalization(code)
                })
        }
    }
}

private struct LanguageListNodeTransition {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
    let firstTime: Bool
    let isLoading: Bool
    let animated: Bool
}

private func preparedLanguageListNodeTransition(presentationData: PresentationData, from fromEntries: [LanguageListEntry], to toEntries: [LanguageListEntry], selectLocalization: @escaping (String) -> Void, setItemWithRevealedOptions: @escaping (String?, String?) -> Void, firstTime: Bool, isLoading: Bool, forceUpdate: Bool, animated: Bool) -> LanguageListNodeTransition {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries, allUpdated: forceUpdate)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(presentationData: presentationData, selectLocalization: selectLocalization, setItemWithRevealedOptions: setItemWithRevealedOptions), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(presentationData: presentationData, selectLocalization: selectLocalization, setItemWithRevealedOptions: setItemWithRevealedOptions), directionHint: nil) }
    
    return LanguageListNodeTransition(deletions: deletions, insertions: insertions, updates: updates, firstTime: firstTime, isLoading: isLoading, animated: animated)
}

final class LanguageControllerNode: ViewControllerTracingNode {
    private let context: AccountContext
    private var presentationData: PresentationData
    private let navigationBar: NavigationBar
    private let present: (ViewController, Any?) -> Void
    private let selectLanguage: (String) -> Void
    
    private var didSetReady = false
    let _ready = ValuePromise<Bool>()
    
    private var containerLayout: (ContainerViewLayout, CGFloat)?
    let listNode: ListView
    private var queuedTransitions: [LanguageListNodeTransition] = []
    private var activityIndicator: ActivityIndicator?
    
    private let presentationDataValue = Promise<PresentationData>()
    private var updatedDisposable: Disposable?
    private var listDisposable: Disposable?
    private let applyDisposable = MetaDisposable()
    
    private let applyingCode = Promise<String?>(nil)
    private let isEditing = ValuePromise<Bool>(false)
    private var isEditingValue: Bool = false {
        didSet {
            self.isEditing.set(self.isEditingValue)
        }
    }
    
    init(context: AccountContext, presentationData: PresentationData, navigationBar: NavigationBar, present: @escaping (ViewController, Any?) -> Void, selectLanguage: @escaping (String) -> Void) {
        self.context = context
        self.presentationData = presentationData
        self.presentationDataValue.set(.single(presentationData))
        self.navigationBar = navigationBar
        self.present = present
        self.selectLanguage = selectLanguage

        self.listNode = ListView()
        self.listNode.keepTopItemOverscrollBackground = ListViewKeepTopItemOverscrollBackground(color: presentationData.theme.chatList.backgroundColor, direction: true)
        
        super.init()
        
        self.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        self.addSubnode(self.listNode)
        
        let revealedCode = Promise<String?>(nil)
        var revealedCodeValue: String?
        let setItemWithRevealedOptions: (String?, String?) -> Void = { id, fromId in
            if (id == nil && fromId == revealedCodeValue) || (id != nil && fromId == nil) {
                revealedCodeValue = id
                revealedCode.set(.single(id))
            }
        }
        
        let preferencesKey: PostboxViewKey = .preferences(keys: Set([PreferencesKeys.localizationListState]))
        let previousEntriesHolder = Atomic<([LanguageListEntry], PresentationTheme, PresentationStrings)?>(value: nil)
        self.listDisposable = combineLatest(queue: .mainQueue(), context.account.postbox.combinedView(keys: [preferencesKey]), context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.localizationSettings]), self.presentationDataValue.get(), self.applyingCode.get(), revealedCode.get(), self.isEditing.get()).start(next: { [weak self] view, sharedData, presentationData, applyingCode, revealedCode, isEditing in
            guard let strongSelf = self else {
                return
            }
            
            var entries: [LanguageListEntry] = []
            var activeLanguageCode: String?
            if let localizationSettings = sharedData.entries[SharedDataKeys.localizationSettings] as? LocalizationSettings {
                activeLanguageCode = localizationSettings.primaryComponent.languageCode
            }

            if let localizationListState = (view.views[preferencesKey] as? PreferencesView)?.values[PreferencesKeys.localizationListState] as? LocalizationListState, !localizationListState.availableOfficialLocalizations.isEmpty {
                
                var languageInfos: [LanguageInfo] = []
                languageInfos.append(LanguageInfo(title: "Chinese", subtitle: "简体中文", code: "classic-zh-cn"))
                languageInfos.append(LanguageInfo(title: "Japanese", subtitle: "日本語", code: "ja-beta"))
                
                for info in languageInfos {
                    entries.append(.localization(index: entries.count, title: info.title, subtitle: info.subtitle, code: info.code, selected: false, activity: false, revealed: false, editing: false))
                }
            }
            let previousEntriesAndPresentationData = previousEntriesHolder.swap((entries, presentationData.theme, presentationData.strings))
            let transition = preparedLanguageListNodeTransition(presentationData: presentationData, from: previousEntriesAndPresentationData?.0 ?? [], to: entries, selectLocalization: { [weak self] info in self?.selectLocalization(info) }, setItemWithRevealedOptions: setItemWithRevealedOptions, firstTime: previousEntriesAndPresentationData == nil, isLoading: entries.isEmpty, forceUpdate: previousEntriesAndPresentationData?.1 !== presentationData.theme || previousEntriesAndPresentationData?.2 !== presentationData.strings, animated: (previousEntriesAndPresentationData?.0.count ?? 0) >= entries.count)
            strongSelf.enqueueTransition(transition)
        })
        self.updatedDisposable = synchronizedLocalizationListState(postbox: context.account.postbox, network: context.account.network).start()
    }
    
    deinit {
        self.listDisposable?.dispose()
        self.updatedDisposable?.dispose()
        self.applyDisposable.dispose()
    }
    
    func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData
        self.presentationDataValue.set(.single(presentationData))
        self.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        self.listNode.keepTopItemOverscrollBackground = ListViewKeepTopItemOverscrollBackground(color: presentationData.theme.chatList.backgroundColor, direction: true)
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let hadValidLayout = self.containerLayout != nil
        self.containerLayout = (layout, navigationBarHeight)
        
        var listInsets = layout.insets(options: [.input])
        listInsets.top += navigationBarHeight
        listInsets.left += layout.safeInsets.left
        listInsets.right += layout.safeInsets.right
        
        self.listNode.bounds = CGRect(x: 0.0, y: 0.0, width: layout.size.width, height: layout.size.height)
        self.listNode.position = CGPoint(x: layout.size.width / 2.0, y: layout.size.height / 2.0)
        
        let (duration, curve) = listViewAnimationDurationAndCurve(transition: transition)
        let updateSizeAndInsets = ListViewUpdateSizeAndInsets(size: layout.size, insets: listInsets, duration: duration, curve: curve)
        
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: nil, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        if let activityIndicator = self.activityIndicator {
            let indicatorSize = activityIndicator.measure(CGSize(width: 100.0, height: 100.0))
            transition.updateFrame(node: activityIndicator, frame: CGRect(origin: CGPoint(x: floor((layout.size.width - indicatorSize.width) / 2.0), y: updateSizeAndInsets.insets.top + 50.0 + floor((layout.size.height - updateSizeAndInsets.insets.top - updateSizeAndInsets.insets.bottom - indicatorSize.height - 50.0) / 2.0)), size: indicatorSize))
        }
        
        if !hadValidLayout {
            self.dequeueTransitions()
        }
    }
    
    private func enqueueTransition(_ transition: LanguageListNodeTransition) {
        self.queuedTransitions.append(transition)
        
        if self.containerLayout != nil {
            self.dequeueTransitions()
        }
    }
    
    private func dequeueTransitions() {
        guard let (layout, navigationBarHeight) = self.containerLayout else {
            return
        }
        while !self.queuedTransitions.isEmpty {
            let transition = self.queuedTransitions.removeFirst()
            
            var options = ListViewDeleteAndInsertOptions()
            if transition.firstTime {
                options.insert(.Synchronous)
                options.insert(.LowLatency)
            } else if transition.animated {
                options.insert(.AnimateInsertion)
            }
            self.listNode.transaction(deleteIndices: transition.deletions, insertIndicesAndItems: transition.insertions, updateIndicesAndItems: transition.updates, options: options, updateOpaqueState: nil, completion: { [weak self] _ in
                if let strongSelf = self {
                    if !strongSelf.didSetReady {
                        strongSelf.didSetReady = true
                        strongSelf._ready.set(true)
                    }
                    
                    if transition.isLoading, strongSelf.activityIndicator == nil {
                        let activityIndicator = ActivityIndicator(type: .custom(strongSelf.presentationData.theme.list.itemAccentColor, 22.0, 1.0, false))
                        strongSelf.activityIndicator = activityIndicator
                        strongSelf.insertSubnode(activityIndicator, aboveSubnode: strongSelf.listNode)
                        
                        strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
                    } else if !transition.isLoading, let activityIndicator = strongSelf.activityIndicator {
                        strongSelf.activityIndicator = nil
                        activityIndicator.removeFromSupernode()
                    }
                }
            })
        }
    }
    
    private func selectLocalization(_ identifier: String) -> Void {
        self.selectLanguage(identifier)
    }
    
    func toggleEditing() {
        self.isEditingValue = !self.isEditingValue
    }
    
    func scrollToTop() {
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: ListViewScrollToItem(index: 0, position: .top(0.0), animated: true, curve: .Default(duration: nil), directionHint: .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
    }
}
