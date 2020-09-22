import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import SyncCore

// oc keyboard
private enum ChatAttachmentAction {
    case photos
    case camera
    case files
    case location
    case contacts
    case vote
}

private enum FacegramConversation {
    case user
    case supergroup
    case broadcast
    case secretchat
    case system
    case bot
    case reviewer
    case selfisreviewer
}

private final class ChatAttachmentKeyboardInputButtonModel {
    var title: String?
    var imageName: String?
    var highlightImageName: String?
    var action: ChatAttachmentAction?
}

private final class ChatAttachmentKeyboardInputButtonNode: ASButtonNode {
    var action: ChatAttachmentAction?
    
    private var theme: PresentationTheme?
    
    init(theme: PresentationTheme) {
        super.init()
        
        self.updateTheme(theme: theme)
    }
    
    func updateTheme(theme: PresentationTheme) {
        if theme !== self.theme {
            self.theme = theme
            
            self.setBackgroundImage(PresentationResourcesChat.chatInputButtonPanelButtonImage(theme), for: [])
            self.setBackgroundImage(PresentationResourcesChat.chatInputButtonPanelButtonHighlightedImage(theme), for: [.highlighted])
        }
    }
}

final class ChatAttachmentKeyboardInputNode: ChatInputNode, UIScrollViewDelegate {
    private let context: AccountContext
    private let controllerInteraction: ChatControllerInteraction
    
    private let separatorNode: ASDisplayNode
    private let scrollNode: ASScrollNode
    private let pageControlNode: PageControlNode
    
    private var buttonNodes: [ChatAttachmentKeyboardInputButtonNode] = []
    private var message: Message?
    
    private var theme: PresentationTheme?
    
    private var panRecognizer: UIPanGestureRecognizer?
    private let chatLocation:ChatLocation
    
    fileprivate var keyboardDataSource: [ChatAttachmentKeyboardInputButtonModel] = []
    fileprivate func loadKeyboardDataSource(mode: FacegramConversation) {
        
        var titles: [String] = []
        var imageNames: [String] = []
        var highlightImageNames: [String] = []
        var actions: [ChatAttachmentAction] = []
        
        let presentationData = self.context.sharedContext.currentPresentationData.with{ $0 }
       
        // 照片
        titles.append(presentationData.strings.AutoDownloadSettings_Photos)
        imageNames.append("Facegram/keyboard_photo")
        highlightImageNames.append("Facegram/keyboard_photo")
        actions.append(.photos)
        
        // 拍照
        titles.append(presentationData.strings.AutoDownloadSettings_Videos)
        imageNames.append("Facegram/keyboard_camera")
        highlightImageNames.append("Facegram/keyboard_camera")
        actions.append(.camera)
      
        // 文件
        titles.append(presentationData.strings.AttachmentMenu_File)
        imageNames.append("Facegram/keyboard_file")
        highlightImageNames.append("Facegram/keyboard_file")
        actions.append(.files)

        // 位置
        titles.append(presentationData.strings.Conversation_Location)
        imageNames.append("Facegram/keyboard_location")
        highlightImageNames.append("Facegram/keyboard_location")
        actions.append(.location)
        
        // 联系人
        titles.append(presentationData.strings.Conversation_Contact)
        imageNames.append("Facegram/keyboard_contacts")
        highlightImageNames.append("Facegram/keyboard_contacts")
        actions.append(.contacts)
        
        // 投票
        if mode == .supergroup {
            titles.append(presentationData.strings.AttachmentMenu_Poll)
            imageNames.append("Facegram/keyboard_poll")
            highlightImageNames.append("Facegram/keyboard_poll")
            actions.append(.vote)
        }
        
        assert(titles.count == imageNames.count)
        assert(imageNames.count == highlightImageNames.count)
        assert(highlightImageNames.count == actions.count)
        
        var keyboardDataSource = [ChatAttachmentKeyboardInputButtonModel]()
        for index in 0 ..< titles.count {
            let model = ChatAttachmentKeyboardInputButtonModel()
            model.title = titles[index]
            model.imageName = imageNames[index]
            model.highlightImageName = highlightImageNames[index]
            model.action = actions[index]
            keyboardDataSource.append(model)
        }
        
        self.keyboardDataSource = keyboardDataSource
    }
    
    init(context: AccountContext, controllerInteraction: ChatControllerInteraction, chatLocation:ChatLocation) {
        self.context = context
        self.controllerInteraction = controllerInteraction
        self.chatLocation = chatLocation
        
        self.scrollNode = ASScrollNode()
        
        self.pageControlNode = PageControlNode(dotSize: 7.0, dotSpacing: 9.0, dotColor: .blue, inactiveDotColor: .gray)
        
        self.separatorNode = ASDisplayNode()
        self.separatorNode.isLayerBacked = true
        
        super.init()
        
        self.addSubnode(self.scrollNode)
        self.scrollNode.view.delaysContentTouches = false
        self.scrollNode.view.canCancelContentTouches = true
        self.scrollNode.view.alwaysBounceHorizontal = false
        self.scrollNode.view.alwaysBounceVertical = false
        
        self.addSubnode(self.separatorNode)
        
        self.pageControlNode.pagesCount = Int((self.keyboardDataSource.count + 7) / 8)
        self.addSubnode(self.pageControlNode)
    }
    
    override func didLoad() {
        super.didLoad()
        
        if #available(iOSApplicationExtension 11.0, iOS 11.0, *) {
            self.scrollNode.view.contentInsetAdjustmentBehavior = .never
        }
        //TGNB
        self.view.disablesInteractiveTransitionGestureRecognizer = true // 禁用返回手势 👍
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:)))
        self.panRecognizer = panRecognizer
        self.view.addGestureRecognizer(panRecognizer)
        
        self.pageControlNode.setPage(0.0)
    }
    
    @objc func panGesture(_ recognizer: UIPanGestureRecognizer) {
        /*
        switch recognizer.state {
            case .ended:
                let page = Int(self.scrollNode.view.contentOffset.x / self.scrollNode.view.frame.size.width)
                let x = self.scrollNode.view.frame.size.width * CGFloat(page)
                if x == 0 {
                    self.scrollNode.view.setContentOffset(CGPoint(), animated: false)
                } else {
                    self.scrollNode.view.setContentOffset(CGPoint(x: x, y: 0), animated: false)
                }
            default:
                break
        }
        */
    }
    
    override func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, bottomInset: CGFloat, standardInputHeight: CGFloat, inputHeight: CGFloat, maximumHeight: CGFloat, inputPanelHeight: CGFloat, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState, deviceMetrics: DeviceMetrics, isVisible: Bool) -> (CGFloat, CGFloat) {
        
        transition.updateFrame(node: self.separatorNode, frame: CGRect(origin: CGPoint(), size: CGSize(width: width, height: UIScreenPixel)))
        
        if self.theme !== interfaceState.theme {
            self.theme = interfaceState.theme
            
            self.separatorNode.backgroundColor = interfaceState.theme.chat.inputButtonPanel.panelSeparatorColor
            self.backgroundColor = interfaceState.theme.chat.inputButtonPanel.panelBackgroundColor
        }
        
        var conversation: FacegramConversation = .reviewer
        if let renderedPeer: RenderedPeer = interfaceState.renderedPeer {
            if let peer = renderedPeer.peer as? TelegramUser {
                if 777000 == peer.id.id {
                    conversation = .system
                } else if let _ = peer.botInfo {
                    conversation = .bot
                } else {
                    conversation = .user
                }
            }
            if let _ = renderedPeer.peer as? TelegramSecretChat {
                conversation = .secretchat
            }
            if let peer = renderedPeer.peer as? TelegramChannel {
                if case .broadcast = peer.info {
                    conversation = .broadcast
                }  else {
                    conversation = .supergroup
                }
            }
        }
        
        self.loadKeyboardDataSource(mode: conversation)
       
        let panelHeight:CGFloat = 242.0
        let pageControlHeight: CGFloat = 20.0
        let maxCols = 4
        let sideInset: CGFloat = 18.0 + leftInset
        let buttonWidth: CGFloat = 59.0
        let columnSpacing: CGFloat = floor(((width - sideInset - sideInset) - CGFloat(maxCols) * buttonWidth) / CGFloat(maxCols - 1))
        let buttonHeight:CGFloat = 58 + 5.0 + 16.5
        
        let keyboardVerticalSpaceing :CGFloat = 10.0
        let rowSpacing: CGFloat = 19.0
        
        for buttonIndex in 0 ..< self.keyboardDataSource.count {
            let buttonNode: ChatAttachmentKeyboardInputButtonNode
            if buttonIndex < self.buttonNodes.count {
                buttonNode = self.buttonNodes[buttonIndex]
                let model = self.keyboardDataSource[buttonIndex]
                buttonNode.setTitle(model.title ?? "", with: Font.regular(12), with: self.theme?.chat.inputButtonPanel.buttonTextColor ?? .black, for: [])
                buttonNode.setImage(UIImage(bundleImageName: model.imageName ?? ""), for: .normal)
                buttonNode.setImage(UIImage(bundleImageName: model.highlightImageName ?? ""), for: .highlighted)
                buttonNode.setBackgroundImage(self.colorImage(color: .clear), for: [])
            } else {
                let model = self.keyboardDataSource[buttonIndex]
                buttonNode = ChatAttachmentKeyboardInputButtonNode(theme: interfaceState.theme)
                buttonNode.laysOutHorizontally = false
                buttonNode.contentSpacing = 5.0
                buttonNode.setTitle(model.title ?? "", with: Font.regular(12), with: self.theme?.chat.inputButtonPanel.buttonTextColor ?? .black, for: [])
                buttonNode.setImage(UIImage(bundleImageName: model.imageName ?? ""), for: .normal)
                buttonNode.setImage(UIImage(bundleImageName: model.highlightImageName ?? ""), for: .highlighted)
                buttonNode.setBackgroundImage(self.colorImage(color: .clear), for: [])
                buttonNode.action = model.action
                buttonNode.addTarget(self, action: #selector(self.buttonPressed(_:)), forControlEvents: [.touchUpInside])
                self.scrollNode.addSubnode(buttonNode)
                self.buttonNodes.append(buttonNode)
            }
            
            var x = 0
            var y = 0
            if buttonIndex < 8 {
                x = Int(sideInset) + (buttonIndex % maxCols) * Int((buttonWidth + columnSpacing))
                if ((buttonIndex / 4) % 2) != 0 {
                    y = Int(rowSpacing) + (buttonIndex / maxCols) * (Int(buttonHeight + keyboardVerticalSpaceing))
                }else{
                    y = Int(rowSpacing) + (buttonIndex / maxCols) * (Int(buttonHeight + rowSpacing))
                }
            }
            else
            {
                x = Int(sideInset) + (buttonIndex % maxCols) * Int((buttonWidth + columnSpacing)) + Int(width)
                if ((buttonIndex / 4) % 2) != 0 {
                    y = Int(rowSpacing) + ((buttonIndex - 8) / maxCols) * (Int(buttonHeight + keyboardVerticalSpaceing))
                }else{
                    y = Int(rowSpacing) + ((buttonIndex - 8) / maxCols) * (Int(buttonHeight + rowSpacing))
                }
            }
            
            buttonNode.frame = CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(buttonWidth), height: CGFloat(buttonHeight))
        }
       
        transition.updateFrame(node: self.scrollNode, frame: CGRect(origin: CGPoint(), size: CGSize(width: width, height: panelHeight)))
        self.scrollNode.view.contentSize = CGSize(width: width * CGFloat(Int((self.keyboardDataSource.count + 7) / 8)), height: panelHeight)
        self.scrollNode.view.isPagingEnabled = true //分页滑动
        self.scrollNode.view.isDirectionalLockEnabled = true//滑动方向锁定
        self.scrollNode.view.showsVerticalScrollIndicator = false
        self.scrollNode.view.showsHorizontalScrollIndicator = false
        self.scrollNode.view.setContentOffset(CGPoint(), animated: false)
        self.scrollNode.view.delegate = self
        
        self.pageControlNode.dotColor = interfaceState.theme.rootController.navigationBar.accentTextColor
        let pageControlSize = self.pageControlNode.measure(CGSize(width: width, height: pageControlHeight))
        self.pageControlNode.frame = CGRect(origin: CGPoint(x: floor((width - pageControlSize.width) / 2.0), y: panelHeight - bottomInset - pageControlSize.height - 23.0), size: pageControlSize)
        
        return (panelHeight, 0.0)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let bounds = self.scrollNode.view.bounds
        if !bounds.width.isZero {
            self.pageControlNode.setPage(self.scrollNode.view.contentOffset.x / bounds.width)
        }
    }
    
    func colorImage(color: UIColor) -> UIImage{
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        UIGraphicsBeginImageContext(rect.size)
        if let context = UIGraphicsGetCurrentContext() {
            context.setFillColor(color.cgColor)
            context.fill(rect)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return image!
        }
        
        return UIImage()
    }
    
    @objc func buttonPressed(_ button: ASButtonNode) {
        if let button = button as? ChatAttachmentKeyboardInputButtonNode, let action = button.action {
            switch action {
                case .photos:
                    self.controllerInteraction.openPhotos()
                case .camera:
                    self.controllerInteraction.openCamera()
                case .files:
                    self.controllerInteraction.openFiles()
                case .location:
                    self.controllerInteraction.openLocation()
                case .contacts:
                    self.controllerInteraction.openContacts()
                case .vote:
                    self.controllerInteraction.openVote()
            }
        }
    }
}
