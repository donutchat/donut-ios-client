//
//  MessagesTableViewController.swift
//  Donut Client
//
//  Created by Allan Garcia on 29/06/17.
//  Copyright © 2017 Allan Garcia. All rights reserved.
//

import UIKit
import Alamofire
import SwiftyJSON
import CoreData
import ActionCableClient


class MessagesTableViewController: FetchedResultsTableViewController {

    // MARK: - Constants
    
    private struct Constants {
        
        static let tableViewMessageCellIdentifier: String = "Message Cell"
        
    }
    
    // MARK: - Outlets
    
    @IBOutlet var messageInputView: UIView!
    
    @IBOutlet weak var messageTextField: UITextField!
    
    // MARK: - Actions
    
    @IBAction func send(_ sender: UIButton) {
        if let messageText = messageTextField.text, messageTextField.text != "" {
            sendMessageWith(text: messageText)
            messageTextField.text = ""
        }
    }
    
    // MARK: - Model
    
    var room: Room? {
        didSet {
            title = room?.title
            debugPrint("ROOM: ", room ?? "Not Setted.")
        }
    }
    
    // MARK: - Network
    
    private func requestMessagesAsync(with token: String) {
        
        let roomIdentifier = String((room?.id)!)
        
        let headers: HTTPHeaders = [
            "Authorization": "Token \(token)",
            "Accept": "application/json"
        ]
        
        Alamofire.request(DonutServer.Constants.listMessagesService.replacingOccurrences(of: ":room_id", with: roomIdentifier),
                          method: .get,
                          headers: headers)
            .validate(statusCode: 200..<300)
            .validate(contentType: ["application/json"])
            .responseJSON { [weak self] response in
                
                switch response.result {
                    
                case .success(let data):
                    
                    debugPrint("SUCCESS: ", data)
                    
                    let json = JSON(data)
                    
                    self?.container?.performBackgroundTask { context in
                        for (_, jsonObject):(String, JSON) in json {
                            _ = try? Message.findOrCreateMessage(with: jsonObject, in: context)
                        }
                        try? context.save()
                        
//                        DispatchQueue.main.async {
//                            self?.refreshControl?.endRefreshing()
//                        }
                    }
                    
                case .failure(let error):
                    
                    debugPrint("ERROR: ", error)
                    
                }
                
        }
        
    }
    
    private var client: ActionCableClient!
    
    private var channel: Channel?
    
    // MARK: - Private Implementation
    
    private func sendMessageWith(text: String) {
        guard let channel = channel else { return }
        // send message
        let roomIdentifier = Int((room?.id)!)
        if let error = channel.action("send_message", with: ["content": text, "room_id": roomIdentifier]) {
            debugPrint("ERROR: ", error)
        }
    }
    
    private func requestMessagesIfAlreadyAuthenticated() {
        if DonutServer.isAuthenticated {
            requestMessagesAsync(with: DonutServer.token!)
        }
    }
    
    private func setupActionCable() {
        
        client = ActionCableClient(
            url: URL(string: DonutServer.Constants.actionCableEndPoint)!
        )
        client.headers = [
            "token": DonutServer.token!
        ]
        client.connect()
        
        client.onConnected = { [weak self] in
            print("Connected!")
            
            let roomIdentifier = Int((self?.room?.id)!)
            self?.channel = self?.client.create(DonutServer.Constants.actionCableChannelClass,
                                                identifier: ["room_id": roomIdentifier],
                                                autoSubscribe: true,
                                                bufferActions: true)
            
            if let channel = self?.channel {
                
                channel.onReceive = { (receivedJson : Any?, error : Error?) in
                    
                    if error != nil {
                        debugPrint("ERROR: ", error!)
                        return
                    }
                    
                    debugPrint("RESPONSE: ", receivedJson ?? "")
                    
                    if receivedJson != nil {
                        
                        let jsonMessage = JSON(receivedJson!)["message"]
                        
                        if let context = self?.container?.viewContext {
                            context.perform {
                                _ = try? Message.findOrCreateMessage(with: jsonMessage, in: context)
                                try? context.save()
                                
                                self?.tableView.reloadData()
                                self?.scrollTableViewToBottom()
                                
                            }
                        }
                        
                    }
                    
                }
                
                channel.onSubscribed = {
                    print("Subscribed")
                }
                
                channel.onUnsubscribed = {
                    print("Unsubscribed")
                }
                
                channel.onRejected = {
                    print("Rejected")
                }
            }
        }
        
        client.onDisconnected = {(error: Error?) in
            print("Disconnected!")
            
            if error != nil {
                debugPrint("ERROR: ", error!)
            }
            
        }

    }
    
    private func setupContainerView() {
        let containerView = ContainerView()
        containerView.customInputView = messageInputView
        view.addSubview(containerView)
        containerView.becomeFirstResponder()
    }
    
    private func scrollTableViewToBottom(animated: Bool = true) {
        let lastSectionIndex = (fetchedResultsController?.sections?.count)! - 1
        let lastRowIndex = (fetchedResultsController?.fetchedObjects?.count)! - 1
        if lastSectionIndex >= 0, lastRowIndex >= 0 {
            let indexPathToLastRow = IndexPath(row: lastRowIndex, section: lastSectionIndex)
            tableView?.scrollToRow(at: indexPathToLastRow, at: .bottom, animated: animated)
        }
    }
    
    // MARK: - View Lifecycle
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        requestMessagesIfAlreadyAuthenticated()
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillShow(_:)),
                                               name: .UIKeyboardWillShow,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillHide(_:)),
                                               name: .UIKeyboardWillHide,
                                               object: nil)
        
        updateFetchedResultsController()
        setupActionCable()
        setupContainerView()
        scrollTableViewToBottom(animated: false)
        
    }
    
    // MARK: - Notifications
    
    @objc func keyboardWillShow(_ notification: Notification) {
        DispatchQueue.main.async {
            self.scrollTableViewToBottom()
        }
    }
    
    @objc func keyboardWillHide(_ notification: Notification) {
        DispatchQueue.main.async {
            self.scrollTableViewToBottom()
        }
    }

    // MARK: - UITableViewController

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.tableViewMessageCellIdentifier, for: indexPath)
        
        if let message = fetchedResultsController?.object(at: indexPath) {
            if let content = message.content {
                cell.textLabel?.text = content
            }
        }
        
        return cell
    }
    
    // MARK: - CoreData
    
    var container: NSPersistentContainer? = (UIApplication.shared.delegate as? AppDelegate)?.persistentContainer
    
    var fetchedResultsController: NSFetchedResultsController<Message>?
    
    private func updateFetchedResultsController() {
        
        if let context = container?.viewContext {
            
            context.automaticallyMergesChangesFromParent = true
            
            let request: NSFetchRequest<Message> = Message.fetchRequest()
            
            request.predicate = NSPredicate(
                format: "room = %@", room!
            )
            
            request.sortDescriptors = [
                NSSortDescriptor(
                    key: "created_at",
                    ascending: true,
                    selector: #selector(NSDate.compare(_:))
                )
            ]
            
            fetchedResultsController = NSFetchedResultsController<Message>(
                fetchRequest: request,
                managedObjectContext: context,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            
            fetchedResultsController?.delegate = self
            
            try? fetchedResultsController?.performFetch()
            
            tableView.reloadData()
            
        }
    }

}


extension MessagesTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return fetchedResultsController?.sections?.count ?? 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let sections = fetchedResultsController?.sections, sections.count > 0 {
            return sections[section].numberOfObjects
        } else {
            return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if let sections = fetchedResultsController?.sections, sections.count > 0 {
            return sections[section].name
        } else {
            return nil
        }
    }
    
    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return fetchedResultsController?.sectionIndexTitles
    }
    
    override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        return fetchedResultsController?.section(forSectionIndexTitle: title, at: index) ?? 0
    }
    
}


class ContainerView: UIView {

    var customInputView: UIView?
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override var inputAccessoryView: UIView? {
        return customInputView
    }
    
}
