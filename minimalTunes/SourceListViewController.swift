//
//  SourceListViewController.swift
//  minimalTunes
//
//  Created by John Moody on 12/1/16.
//  Copyright © 2016 John Moody. All rights reserved.
//

import Cocoa
import MultipeerConnectivity

class SourceListViewController: NSViewController, NSOutlineViewDelegate, NSOutlineViewDataSource, NSTextFieldDelegate {
    
    //pre-Sierra NSOutlineView weakly retains items, hence the need for SourceListNodes
    
    @IBOutlet weak var sourceList: SourceListThatYouCanPressSpacebarOn!
    
    var currentAudioSource: SourceListItem?
    var currentSourceListItem: SourceListItem?
    var sourceListDataSource: SourceListDataSource?
    var sharedLibraryIdentifierDictionary = NSMutableDictionary()
    var requestedSharedPlaylists = NSMutableDictionary()
    var mainWindowController: MainWindowController?
    var server: ConnectivityManager?
    
    var rootNode: SourceListNode?
    
    var draggedNodes: [SourceListNode]?
    var libraryHeaderNode: SourceListNode?
    var playlistHeaderNode: SourceListNode?
    var sharedHeaderNode: SourceListNode?
    
    
    lazy var rootSourceListItem: SourceListItem? = {
        let request = NSFetchRequest(entityName: "SourceListItem")
        do {
            let predicate = NSPredicate(format: "is_root == true")
            request.predicate = predicate
            let result = try self.managedContext.executeFetchRequest(request) as! [SourceListItem]
            if result.count > 0 {
                return result[0]
            } else {
                return nil
            }
        } catch {
            print("error getting library: \(error)")
            return nil
        }
    }()
    
    lazy var managedContext: NSManagedObjectContext = {
        return (NSApplication.sharedApplication().delegate
            as? AppDelegate)?.managedObjectContext }()!
    
    func createTree() {
        var nodesNotVisited = [SourceListItem]()
        nodesNotVisited.append(rootSourceListItem!)
        while !nodesNotVisited.isEmpty {
            let item = nodesNotVisited.removeFirst()
            let node = SourceListNode(item: item)
            if item == rootSourceListItem {
                rootNode = node
            }
            if item.parent != nil {
                node.parent = item.parent?.node
                node.parent?.children.append(node)
            }
            for child in item.children! {
                nodesNotVisited.append(child as! SourceListItem)
            }
        }
        print("done making tree")
    }
    
    func sortTree() {
        var nodesNotVisited = [SourceListNode]()
        nodesNotVisited.append(rootNode!)
        while nodesNotVisited.isEmpty == false {
            let node = nodesNotVisited.removeFirst()
            node.children.sortInPlace({return Int($0.item.sort_order!) < Int($1.item.sort_order!)})
            for node in node.children {
                if node.children.count > 0 {
                    nodesNotVisited.append(node)
                }
            }
        }
    }
    
    func getCurrentSelection() -> SourceListNode {
        let node = self.sourceList.itemAtRow(sourceList.selectedRow) as! SourceListNode
        return node
    }
    
    func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
        if item == nil {
            if rootNode == nil {
                return 0
            }
            var count = 0
            for item in rootNode!.children {
                if item.children.count > 0 {
                    count += 1
                }
            }
            return count
        }
        let source = item as! SourceListNode
        return source.children.count
    }
    func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
        let source = item as! SourceListNode
        if source.children.count > 0 {
            return true
        } else {
            return false
        }
    }
    
    func outlineView(outlineView: NSOutlineView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, byItem item: AnyObject?) {
        print("set object value called")
    }
    
    override func controlTextDidEndEditing(obj: NSNotification) {
        let node = sourceList.itemAtRow(sourceList.rowForView(obj.object as! NSTextField)) as! SourceListNode
        node.item.name = (obj.object as! NSTextField).stringValue
    }
    
    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
        if item == nil {
            if rootNode!.children[index].children.count > 0 {
                return rootNode!.children[index]
            } else {
                return rootNode!.children[index+1]
            }
        }
        let source = item as! SourceListNode
        let child = source.children[index]
        return child
    }
    
    func outlineView(outlineView: NSOutlineView, shouldEditTableColumn tableColumn: NSTableColumn?, item: AnyObject) -> Bool {
        print("should edit called")
        return true
    }
    
    func getNodesBeforePlaylists() -> Int {
        var index = 0
        var found = false
        while found == false && sourceList.itemAtRow(index) != nil {
            let item = sourceList.itemAtRow(index) as! SourceListNode
            if item.item.parent == playlistHeaderNode!.item {
                found = true
            } else {
                index += 1
            }
        }
        return index
    }
    
    func createPlaylistFolder(nodes: [SourceListNode]?) {
        let playlistFolderItem = NSEntityDescription.insertNewObjectForEntityForName("SourceListItem", inManagedObjectContext: managedContext) as! SourceListItem
        playlistFolderItem.is_folder = true
        let playlistFolderNode = SourceListNode(item: playlistFolderItem)
        playlistFolderItem.name = "New Playlist Folder"
        playlistFolderItem.parent = rootNode?.children[2].item
        if nodes != nil {
            makeNodesSubnodesOfNode(nodes!, parentNode: playlistFolderNode, index: 0)
        }
        playlistHeaderNode?.children.insert(playlistFolderNode, atIndex: 0)
        sourceList.reloadData()
        let newPlaylistIndex = NSIndexSet(index: getNodesBeforePlaylists())
        sourceList.selectRowIndexes(newPlaylistIndex, byExtendingSelection: false)
        sourceList.editColumn(0, row: sourceList.selectedRow, withEvent: nil, select: true)
    }
    
    func makeNodesSubnodesOfNode(nodes: [SourceListNode], parentNode: SourceListNode, index: Int) {
        let parentItem = parentNode.item
        let itemsToBeAdded = nodes.map({return $0.item})
        let newItemChildren: NSMutableOrderedSet = parentItem.children?.count > 0 ? parentItem.children?.mutableCopy() as! NSMutableOrderedSet : NSMutableOrderedSet()
        var mutableIndex = index
        for item in itemsToBeAdded {
            guard item != parentNode.item else {continue}
            let currentParentNode = item.node!.parent!
            let currentParentItem = item.node!.parent!.item
            //remove from sibling sets for both items and nodes, then reset parents
            let currentNodeSiblingIndex = currentParentNode.children.indexOf(item.node!)
            currentParentNode.children.removeAtIndex(currentNodeSiblingIndex!)
            let currentItemSiblingsMutableCopy = currentParentItem.children!.mutableCopy() as! NSMutableOrderedSet
            currentItemSiblingsMutableCopy.removeObject(item)
            currentParentItem.children = currentItemSiblingsMutableCopy as NSOrderedSet
            item.node?.parent = parentNode
            item.parent = parentItem
            //insert into new sibling sets at appropriate index
            newItemChildren.insertObject(item, atIndex: mutableIndex)
            parentNode.children.insert(item.node!, atIndex: mutableIndex)
            mutableIndex += 1
        }
        parentItem.children = newItemChildren as NSOrderedSet
        var index = 0
        for node in parentNode.children {
            node.item.sort_order = index
            index += 1
        }
        sortTree()
        sourceList.reloadData()
    }
    
    func createPlaylist(tracks: [Int]?, smart_criteria: SmartCriteria?) {
        //create playlist
        let playlist = NSEntityDescription.insertNewObjectForEntityForName("SongCollection", inManagedObjectContext: managedContext) as! SongCollection
        let playlistItem = NSEntityDescription.insertNewObjectForEntityForName("SourceListItem", inManagedObjectContext: managedContext) as! SourceListItem
        playlistItem.playlist = playlist
        playlistItem.name = "New Playlist"
        playlistItem.parent = rootNode?.children[2].item
        if tracks != nil {
            playlist.track_id_list = tracks!
        }
        if smart_criteria != nil {
            playlist.smart_criteria = smart_criteria
        }
        //todo ID
        playlist.id = library?.next_playlist_id
        library?.next_playlist_id = Int(library!.next_playlist_id!) + 1
        //create node
        let newSourceListNode = SourceListNode(item: playlistItem)
        playlistHeaderNode?.children.insert(newSourceListNode, atIndex: 0)
        sourceList.reloadData()
        print(getNodesBeforePlaylists())
        let newPlaylistIndex = NSIndexSet(index: getNodesBeforePlaylists())
        sourceList.selectRowIndexes(newPlaylistIndex, byExtendingSelection: false)
        sourceList.editColumn(0, row: sourceList.selectedRow, withEvent: nil, select: true)
    }
    
    func addNetworkedLibrary(peer: MCPeerID) {
        let newSourceListItem = NSEntityDescription.insertNewObjectForEntityForName("SourceListItem", inManagedObjectContext: managedContext) as! SourceListItem
        newSourceListItem.parent = self.rootNode?.children[1].item
        newSourceListItem.name = peer.displayName
        newSourceListItem.is_network = true
        let newLibrary = NSEntityDescription.insertNewObjectForEntityForName("Library", inManagedObjectContext: managedContext) as! Library
        newLibrary.is_network = true
        newLibrary.name = peer.displayName
        newLibrary.peer = peer
        newSourceListItem.library = newLibrary
        let newSourceListNode = SourceListNode(item: newSourceListItem)
        self.rootNode?.children[1].children.append(newSourceListNode)
        sharedLibraryIdentifierDictionary[peer] = newSourceListNode
        dispatch_async(dispatch_get_main_queue()) {
            self.sourceList.reloadData()
        }
        print("wrote \(peer) to shared library identifier dictionary")
    }
    
    func removeNetworkedLibrary(peer: MCPeerID) {
        guard let node = self.sharedLibraryIdentifierDictionary[peer] as? SourceListNode else {return}
        var nodesNotVisited = [SourceListNode]()
        nodesNotVisited.append(node)
        while !nodesNotVisited.isEmpty {
            let theNode = nodesNotVisited.removeFirst()
            if theNode.item.playlist?.track_id_list != nil {
                //delete network tracks, track views, artist, albums, composers, genres
                let trackViewFetchRequest = NSFetchRequest(entityName: "TrackView")
                let trackViewFetchPredicate = NSPredicate(format: "is_network == true AND track.id in %@", theNode.item.playlist?.track_id_list as! [Int])
                trackViewFetchRequest.predicate = trackViewFetchPredicate
                do {
                    let results = try managedContext.executeFetchRequest(trackViewFetchRequest) as! [TrackView]
                    for thing in results {
                        managedContext.deleteObject(thing.track!)
                        managedContext.deleteObject(thing)
                    }
                } catch {
                    print(error)
                }
            }
            if theNode.children.count > 0 {
                nodesNotVisited.appendContentsOf(theNode.children)
            }
        }
        sharedHeaderNode!.children.removeAtIndex(sharedHeaderNode!.children.indexOf(node)!)
        let deleteFetch = NSFetchRequest(entityName: "SourceListItem")
        let deletePredicate = NSPredicate(format: "is_network == true")
        deleteFetch.predicate = deletePredicate
        do {
            let results = try managedContext.executeFetchRequest(deleteFetch) as! [SourceListItem]
            for result in results {
                if result.library?.peer == peer {
                    managedContext.deleteObject(result)
                }
            }
            try managedContext.save()
        } catch {
            print(error)
        }
        sourceList.reloadData()
    }
    
    func addSourcesForNetworkedLibrary(sourceData: [NSDictionary], peer: MCPeerID) {
        print("looking up \(peer) in shared library identifier dictionary")
        let item = self.sharedLibraryIdentifierDictionary[peer] as! SourceListNode
        //create sourcelistitem
        let masterItem = NSEntityDescription.insertNewObjectForEntityForName("SourceListItem", inManagedObjectContext: managedContext) as! SourceListItem
        masterItem.name = "Music"
        
        masterItem.parent = item.item
        masterItem.is_network = true
        masterItem.library = item.item.library
        //create node for source list tree controller
        let newSourceListNode = SourceListNode(item: masterItem)
        item.children.append(newSourceListNode)
        //create expandable sourcelistitem for playlists
        let playlistsItem = NSEntityDescription.insertNewObjectForEntityForName("SourceListItem", inManagedObjectContext: managedContext) as! SourceListItem
        playlistsItem.name = "Playlists"
        playlistsItem.parent = item.item
        playlistsItem.is_network = true
        playlistsItem.library = item.item.library
        //create node for source list tree controller
        let playlistsItemNode = SourceListNode(item: playlistsItem)
        item.children.append(playlistsItemNode)
        for playlist in sourceData {
            //create sourcelistitem
            let newItem = NSEntityDescription.insertNewObjectForEntityForName("SourceListItem", inManagedObjectContext: managedContext) as! SourceListItem
            newItem.sort_order = playlist["sort_order"] as! Int
            newItem.name = playlist["name"] as? String
            newItem.parent = playlistsItem
            newItem.library = item.item.library
            //create playlist object
            let newPlaylist = NSEntityDescription.insertNewObjectForEntityForName("SongCollection", inManagedObjectContext: managedContext) as! SongCollection
            newPlaylist.id = playlist["id"] as! Int
            newItem.playlist = newPlaylist
            newItem.parent = playlistsItem
            newItem.is_network = true
            //create source list node
            let sourceNode = SourceListNode(item: newItem)
            sourceNode.item = newItem
            playlistsItemNode.children.append(sourceNode)
        }
        dispatch_async(dispatch_get_main_queue()) {
            self.sourceList.reloadData()
        }
    }
    
    func outlineView(outlineView: NSOutlineView, shouldSelectItem item: AnyObject) -> Bool {
        let source = (item as! SourceListNode).item
        if source.is_header == true {
            return false
        } else if source.children?.count > 0 && source.is_folder != true {
            return false
        } else {
            return true
        }
    }
    
    func outlineView(outlineView: NSOutlineView, viewForTableColumn tableColumn: NSTableColumn?, item: AnyObject) -> NSView? {
        let source = item as! SourceListNode
        if (source.item.is_header == true) {
            let view = outlineView.makeViewWithIdentifier("HeaderCell", owner: self) as! SourceListCellView
            view.node = source
            view.textField?.stringValue = source.item.name!
            view.textField?.editable = false
            return view
        } else if source.item.playlist != nil {
            if source.item.playlist?.smart_criteria != nil {
                let view = outlineView.makeViewWithIdentifier("SmartPlaylistCell", owner: self) as! SourceListCellView
                view.node = source
                view.textField?.stringValue = source.item.name!
                view.textField?.delegate = self
                return view
            } else {
                let view = outlineView.makeViewWithIdentifier("PlaylistCell", owner: self) as! SourceListCellView
                view.node = source
                view.textField?.stringValue = source.item.name!
                view.textField?.delegate = self
                return view
            }
        } else if source.item.is_network == true {
            let view = outlineView.makeViewWithIdentifier("NetworkLibraryCell", owner: self) as! SourceListCellView
            view.node = source
            view.textField?.stringValue = source.item.name!
            view.textField?.editable = false
            return view
        } else if source.item.is_folder == true {
            let view = outlineView.makeViewWithIdentifier("PlaylistFolderCell", owner: self) as! SourceListCellView
            view.node = source
            view.textField?.stringValue = source.item.name!
            view.textField?.delegate = self
            view.textField?.editable = true
            return view
        } else if source.item.library != nil {
            let view = outlineView.makeViewWithIdentifier("MasterPlaylistCell", owner: self) as! SourceListCellView
            view.node = source
            view.textField?.stringValue = source.item.name!
            view.textField?.editable = false
            return view
        } else {
            let view = outlineView.makeViewWithIdentifier("PlaylistCell", owner: self) as! SourceListCellView
            view.node = source
            view.textField?.stringValue = source.item.name!
            view.textField?.delegate = self
            return view
        }
    }
    
    func getNetworkPlaylist(id: Int) -> SourceListItem? {
        let item = requestedSharedPlaylists[id] as? SourceListItem
        return item
    }
    
    func getCurrentSelectionSharedLibraryPeer() -> MCPeerID {
        return (sourceList.itemAtRow(sourceList.selectedRow) as! SourceListNode).item.library!.peer as! MCPeerID
    }
    
    func doneAddingNetworkPlaylistCallback(item: SourceListItem) {
        guard currentSourceListItem == item else {return}
        let track_id_list = item.playlist?.track_id_list as? [Int]
        mainWindowController?.networkPlaylistCallback(Int(item.playlist!.id!), idList: track_id_list!)
    }
    
    func outlineViewSelectionDidChange(notification: NSNotification) {
        let selectionNode = (sourceList.itemAtRow(sourceList.selectedRow) as! SourceListNode)
        let selection = selectionNode.item
        self.currentSourceListItem = selection
        let track_id_list = selection.playlist?.track_id_list as? [Int]
        if track_id_list == nil && selection.is_network == true && selection.playlist?.id != nil {
            print("outline view detected network playlist")
            requestedSharedPlaylists[selection.playlist!.id!] = selection
            self.server!.getDataForPlaylist(selectionNode)
        }
        mainWindowController?.switchToPlaylist(selection)
    }
    
    func outlineView(outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAtPoint screenPoint: NSPoint, forItems draggedItems: [AnyObject]) {
        print("called")
    }
    
    func outlineView(outlineView: NSOutlineView, writeItems items: [AnyObject], toPasteboard pasteboard: NSPasteboard) -> Bool {
        print(items)
        draggedNodes = items as? [SourceListNode]
        //for intra-NSOV drags, we do not attach pasteboard data
        pasteboard.setData(nil, forType: "SourceListItem")
        return true
    }
    
    func outlineView(outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: AnyObject?, proposedChildIndex index: Int) -> NSDragOperation {
        print("validate drop called on source list")
        print(info.draggingPasteboard().dataForType("Track"))
        if draggedNodes != nil {
            let node = item as? SourceListNode
            print(index)
            if node?.item.is_folder == true {
                print("returning generic")
                return .Every
            } else if node == playlistHeaderNode && index != -1 {
                print("returning move")
                return .Move
            } else {
                print("returning none")
                return .None
            }
        } else if info.draggingPasteboard().dataForType("Track") != nil {
            print("non nil track data")
            if item != nil && (item as! SourceListNode).item.parent?.name == "Playlists" {
                return .Generic
            }
        } else if info.draggingPasteboard().dataForType("NetworkTrack") != nil {
            print("non nil networktrack data")
            if item != nil {
                let itemParentName = (item as! SourceListNode).item.parent?.name
                print(itemParentName)
                if item != nil && (itemParentName == "Playlists" || itemParentName == "Library") {
                    return .Generic
                }
            }
        }
        print("returning none")
        return .None
    }
    
    func outlineView(outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: AnyObject?, childIndex index: Int) -> Bool {
        if draggedNodes != nil {
            var fixedIndex = index
            if index == -1 {
                fixedIndex = 0
            }
            makeNodesSubnodesOfNode(draggedNodes!, parentNode: item as! SourceListNode, index: fixedIndex)
            draggedNodes = nil
            sourceList.reloadData()
            return true
        } else if info.draggingPasteboard().dataForType("Track") != nil {
            print("doing stuff")
            let playlistItem = (item as! SourceListNode).item
            let playlist = playlistItem.playlist
            let data = info.draggingPasteboard().dataForType("Track")
            let unCodedThing = NSKeyedUnarchiver.unarchiveObjectWithData(data!) as! NSMutableArray
            let tracks = { () -> [Track] in
                var result = [Track]()
                for trackURI in unCodedThing {
                    let id = managedContext.persistentStoreCoordinator?.managedObjectIDForURIRepresentation(trackURI as! NSURL)
                    result.append(managedContext.objectWithID(id!) as! Track)
                }
                return result
            }()
            for track in tracks {
                var id_list: [Int]
                if playlist!.track_id_list != nil {
                    id_list = playlist!.track_id_list as! [Int]
                } else {
                    id_list = [Int]()
                }
                id_list.append(Int(track.id!))
                playlist?.track_id_list = id_list
            }
        } else if info.draggingPasteboard().dataForType("NetworkTrack") != nil {
            print("processing network track transfers")
            let playlistItem = (item as! SourceListNode).item
            let playlist = playlistItem.playlist
            let data = info.draggingPasteboard().dataForType("NetworkTrack")
            let unCodedThing = NSKeyedUnarchiver.unarchiveObjectWithData(data!) as! NSMutableArray
            let tracks = { () -> [Track] in
                var result = [Track]()
                for trackURI in unCodedThing {
                    let id = managedContext.persistentStoreCoordinator?.managedObjectIDForURIRepresentation(trackURI as! NSURL)
                    result.append(managedContext.objectWithID(id!) as! Track)
                }
                return result
            }()
            for track in tracks {
                self.server?.askPeerForSongDownload(currentSourceListItem!.library?.peer as! MCPeerID, track: track)
            }
            
        }
        return true
    }
    
    func selectStuff() {
        let indexSet = NSIndexSet(index: 1)
        sourceList.selectRowIndexes(indexSet, byExtendingSelection: false)
    }
    
    override func viewDidLoad() {
        self.createTree()
        self.sortTree()
        libraryHeaderNode = rootNode?.children[0]
        sharedHeaderNode = rootNode?.children[1]
        playlistHeaderNode = rootNode?.children[2]
        sourceList.setDelegate(self)
        sourceList.setDataSource(self)
        sourceList.autosaveExpandedItems = true
        sourceList.expandItem(libraryHeaderNode)
        sourceList.expandItem(playlistHeaderNode)
        sourceList.reloadData()
        sourceList.allowsEmptySelection = false
        // Do view setup here.
        super.viewDidLoad()
    }

}
