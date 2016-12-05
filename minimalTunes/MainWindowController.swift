//
//  MainWindowController.swift
//  minimalTunes
//
//  Created by John Moody on 5/30/16.
//  Copyright © 2016 John Moody. All rights reserved.
//

import Cocoa
import CoreData
 

private var my_context = 0


class MainWindowController: NSWindowController, NSSearchFieldDelegate {
    
    
    //interface elements
    @IBOutlet weak var trackQueueTargetView: NSView!
    @IBOutlet weak var librarySplitView: NSSplitView!
    @IBOutlet var noMusicView: NSView!
    @IBOutlet weak var artworkTargetView: NSView!
    @IBOutlet weak var sourceListTargetView: NSView!
    @IBOutlet weak var bitRateFormatter: BitRateFormatter!
    @IBOutlet weak var queueButton: NSButton!
    @IBOutlet weak var volumeSlider: NSSlider!
    @IBOutlet weak var progressBarView: ProgressBarView!
    @IBOutlet weak var shuffleButton: NSButton!
    @IBOutlet weak var trackListTriangle: NSButton!
    @IBOutlet weak var progressBar: NSProgressIndicator!
    @IBOutlet weak var songNameLabel: NSTextField!
    @IBOutlet weak var artistAlbumLabel: NSTextField!
    @IBOutlet weak var durationLabel: NSTextField!
    @IBOutlet weak var currentTimeLabel: NSTextField!
    @IBOutlet weak var theBox: NSBox!
    @IBOutlet weak var searchField: NSSearchField!
    @IBOutlet var artCollectionArrayController: NSArrayController!
    @IBOutlet weak var infoField: NSTextField!
    
    //subview controllers
    var sourceListViewController: SourceListViewController?
    var trackQueueViewController: TrackQueueViewController?
    var otherTableViewControllers = NSMutableDictionary()
    var otherSharedTableViewControllers = NSMutableDictionary()
    var currentTableViewController: LibraryTableViewController?
    var libraryTableViewController: LibraryTableViewController?
    var albumArtViewController: AlbumArtViewController?
    var advancedFilterViewController: AdvancedFilterViewController?
    
    //subordinate window controllers
    var tagWindowController: TagEditorWindow?
    var equalizerWindowController: EqualizerWindowController?
    var customFieldController: CustomFieldWindowController?
    var importWindowController: ImportWindowController?
    
    //other variables
    var trackQueue = [Track]()
    var saved_search_bar_content: String?
    var networkedLibraries = NSMutableDictionary()
    var currentAudioSource: SourceListItem?
    var currentSourceListItem: SourceListItem?
    var delegate: AppDelegate?
    var timer: NSTimer?
    var lastTimerDate: NSDate?
    var secsPlayed: NSTimeInterval = 0
    var cur_view_title = "Music"
    var cur_source_title = "Music"
    var duration: Double?
    var paused: Bool? = true
    var is_initialized = false
    var shuffle = NSOnState
    var currentTrack: Track?
    var currentTrackView: TrackView?
    var currentNetworkTrack: Track?
    var currentNetworkTrackView: TrackView?
    var current_source_play_order: [Int]?
    var current_source_temp_shuffle: [Int]?
    var current_source_index: Int?
    var current_source_index_temp: Int?
    var infoString: String?
    var auxArrayController: NSArrayController?
    var hasMusic: Bool = false
    var focusedColumn: NSTableColumn?
    var currentOrder: CachedOrder?
    var newCurrentOrder: NewCachedOrder?
    var asc: Bool?
    var is_streaming = false
    var currentLibrary: Library?
    let numberFormatter = NSNumberFormatter()
    let dateFormatter = NSDateComponentsFormatter()
    let sizeFormatter = NSByteCountFormatter()
    let fileManager = NSFileManager.defaultManager()
    var currentFilterPredicate: NSPredicate?
    
    lazy var cachedOrders: [CachedOrder]? = {
        let request = NSFetchRequest(entityName: "CachedOrder")
        do {
            let result = try managedContext.executeFetchRequest(request) as! [CachedOrder]
            return result
        } catch {
            print(error)
            return nil
        }
    }()
    
    //initialize managed object context
    
    //sort descriptors for source list
    var sourceListSortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(key: "sort_order", ascending: true), NSSortDescriptor(key: "name", ascending: true)]
    
    var librarySortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(key: "artist_sort_order", ascending: true)]
    
    @IBAction func importButtonPressed(sender: AnyObject) {
        importWindowController = ImportWindowController(windowNibName: "ImportWindowController")
        importWindowController?.mainWindowController = self
        importWindowController?.showWindow(self)
    }
    //the view coordinator
    var viewCoordinator: ViewCoordinator?
    
    func searchFieldDidStartSearching(sender: NSSearchField) {
        print("search started searching called")
        viewCoordinator?.search_bar_content = searchField.stringValue
    }
    
    func searchFieldDidEndSearching(sender: NSSearchField) {
        print("search ended searching called")
        viewCoordinator?.search_bar_content = ""
    }
    
    func networkPlaylistCallback(id: Int, idList: [Int]) {
        guard self.otherSharedTableViewControllers.objectForKey(id) != nil else {return}
        let playlistViewController = otherSharedTableViewControllers.objectForKey(id) as! LibraryTableViewController
        playlistViewController.trackViewArrayController.fetchPredicate = NSPredicate(format: "track.id in %@ AND track.is_network == %@", idList, NSNumber(booleanLiteral: true))
        playlistViewController.tableView.reloadData()
    }
    
    func createPlaylistViewController(tracks: [Int], is_network: Bool) -> LibraryTableViewController {
        let newPlaylistViewController = LibraryTableViewController(nibName: "LibraryTableViewController", bundle: nil)
        newPlaylistViewController?.trackViewArrayController.addObserver(self, forKeyPath: "arrangedObjects", options: .New, context: &my_context)
        newPlaylistViewController?.trackViewArrayController.addObserver(self, forKeyPath: "filterPredicate", options: .New, context: &my_context)
        newPlaylistViewController?.trackViewArrayController.fetchPredicate = NSPredicate(format: "track.id in %@ AND track.is_network == %@", tracks, NSNumber(booleanLiteral: is_network))
        return newPlaylistViewController!
    }
    
    func switchToPlaylist(tracks: [Int], id: Int, is_network: Bool) {
        guard self.currentTableViewController?.item?.playlist!.id != id else {return}
        if librarySplitView.arrangedSubviews.contains(libraryTableViewController!.view) {
            librarySplitView.removeArrangedSubview(libraryTableViewController!.view)
        }
        if otherTableViewControllers.objectForKey(id) != nil {
            let playlistViewController = otherTableViewControllers.objectForKey(id) as! LibraryTableViewController
            librarySplitView.addArrangedSubview(playlistViewController.view)
            currentTableViewController = playlistViewController
        } else if otherSharedTableViewControllers.objectForKey(id) != nil {
            let playlistViewController = otherTableViewControllers.objectForKey(id) as! LibraryTableViewController
            librarySplitView.addArrangedSubview(playlistViewController.view)
            currentTableViewController = playlistViewController
        } else {
            let newPlaylistViewController = createPlaylistViewController(tracks, is_network: is_network)
            if is_network {
                self.otherSharedTableViewControllers[id] = newPlaylistViewController
            } else {
                self.otherTableViewControllers[id] = newPlaylistViewController
            }
            librarySplitView.addArrangedSubview(newPlaylistViewController.view)
            currentTableViewController = newPlaylistViewController
        }
    }
    
    func switchToLibrary() {
        librarySplitView.removeArrangedSubview(currentTableViewController!.view)
        librarySplitView.addArrangedSubview(libraryTableViewController!.view)
    }
    
    //track queue, source logic
    @IBAction func toggleExpandQueue(sender: AnyObject) {
        trackQueueViewController!.toggleHidden(queueButton.state)
        switch queueButton.state {
        case NSOnState:
            NSUserDefaults.standardUserDefaults().setBool(false, forKey: "queueHidden")
        default:
            NSUserDefaults.standardUserDefaults().setBool(true, forKey: "queueHidden")
        }
    }
    
    func launchGetInfo(tracks: [Track]) {
        self.tagWindowController = TagEditorWindow(windowNibName: "TagEditorWindow")
        self.tagWindowController?.mainWindowController = self
        self.tagWindowController?.selectedTracks = tracks
        tagWindowController?.showWindow(self)
    }
    
    
    func addTracksToQueue(tracks: [Track]) {
        //todo test for whatever case means you need to start playing immediately
        
        //else
        for track in tracks {
            self.trackQueueViewController!.addTrackToQueue(track, context: cur_view_title, tense: 1)
            delegate?.audioModule.addTrackToQueue(track, index: nil)
            trackQueue.append(track)
        }
        self.trackQueueViewController?.reloadData()
    }
    
    func createPlayOrderArray(track_played: Track) {
        print("initialize array called")
        let selectionItem = sourceListViewController!.getCurrentSelection()
        self.current_source_play_order = libraryTableViewController?.getUpcomingIDsForPlayEvent(self.shuffleButton.state, id: Int(track_played.id!))
        self.current_source_index = 0
        is_initialized = true
        currentAudioSource = selectionItem.item
    }
    
    func modifyPlayOrderForSortDescriptorChange() {
        if currentAudioSource == currentSourceListItem && shuffleButton.state == NSOffState && currentTrack != nil {
            self.current_source_play_order = libraryTableViewController?.getUpcomingIDsForPlayEvent(NSOffState, id: Int(currentTrack!.id!))
        }
    }
    
    func getNextTrack() -> Track? {
        var id: Int?
        if current_source_play_order!.count == current_source_index! + 1 {
            return nil
        } else {
            id = current_source_play_order![current_source_index! + 1]
            current_source_index! += 1
            let next_track = getTrackWithID(id!)
            dispatch_async(dispatch_get_main_queue()) {
                self.currentTrack?.is_playing = false
            }
            self.currentTrack = next_track
            self.currentTrackView = next_track?.view
            return next_track
        }
    }
    
    func getTrackWithID(id: Int) -> Track? {
        let fetch_req = NSFetchRequest(entityName: "Track")
        let pred = NSPredicate(format: "id == \(id)")
        fetch_req.predicate = pred
        let result: Track? = {() -> Track? in
            do {
                return try (managedContext.executeFetchRequest(fetch_req) as! [Track])[0]
            }
            catch {
                return nil
            }
        }()
        return result
    }
    
    @IBAction func shuffleButtonPressed(sender: AnyObject) {
        if (shuffleButton.state == NSOnState) {
            NSUserDefaults.standardUserDefaults().setInteger(NSOnState, forKey: "shuffle")
            print("shuffling")
            current_source_temp_shuffle = current_source_play_order
            shuffle_array(&current_source_temp_shuffle!)
            if (currentTrack != nil) {
                current_source_temp_shuffle = current_source_temp_shuffle!.filter( {
                    $0 != currentTrack!.id
                })
            }
            current_source_index = 0
        }
        else {
            if currentTrack != nil {
                current_source_index = (current_source_play_order?.indexOf(Int(currentTrack!.id!)))! + 1
            } else {
            }
            print("current source index:" + String(current_source_index))
            NSUserDefaults.standardUserDefaults().setInteger(NSOffState, forKey: "shuffle")
        }
    }
    
    @IBAction func addPlaylistButton(sender: AnyObject) {
        sourceListViewController!.createPlaylist(nil)
    }
    
    func createPlaylistFromTracks(idList: [Int]) {
        sourceListViewController?.createPlaylist(idList)
    }
    
    //player stuff
    
    var artworkToggle: NSButton?
    @IBAction func toggleArtwork(sender: AnyObject) {
        albumArtViewController!.toggleHidden(artworkToggle!.state)
    }

    func playNetworkSongCallback() {
        guard self.is_streaming == true else {return}
        delegate?.audioModule.playNetworkImmediately(self.currentTrack!)
        //initializeInterfaceForNewTrack()
        paused = false
    }
    
    func playSong(track: Track) {
        if track.is_network == true {
            self.is_streaming = true
            initializeInterfaceForNetworkTrack()
            let sharedName = sourceListViewController!.getCurrentSelectionSharedLibraryName()
            delegate?.server?.getTrack(Int(track.id!), libraryName: sharedName)
            currentTrack = track
            createPlayOrderArray(track)
            return
        } else {
            self.is_streaming = false
        }
        if (paused == true && delegate?.audioModule.is_initialized == true) {
            unpause()
        }
        createPlayOrderArray(track)
        delegate?.audioModule.playImmediately(track.location!)
        self.currentTrack?.is_playing = false
        self.currentTrack = track
        self.currentTrack?.is_playing = true
        self.currentTrackView = track.view
        paused = false
        currentTrack = track
    }
    
    func shuffle_array(inout array: [Int]) {
        guard array.count > 0 else {return}
        for i in 0..<array.count - 1 {
            let j = Int(arc4random_uniform(UInt32(array.count - i))) + i
            guard i != j else {continue}
            swap(&array[i], &array[j])
        }
    }
    
    func playAnything() {
        let trackToPlay = currentTableViewController!.getTrackWithNoContext(shuffleButton.state)
        if trackToPlay != nil {
            playSong(trackToPlay!)
        }
    }
    
    func interpretSpacebarEvent() {
        if currentTrack != nil {
            if paused == true {
                unpause()
            } else if paused == false {
                pause()
            }
        } else {
            playAnything()
        }
    }
    
    func pause() {
        paused = true
        print("pause called")
        updateValuesUnsafe()
        delegate?.audioModule.pause()
        timer!.invalidate()
    }
    
    func unpause() {
        print("unpause called")
        paused = false
        lastTimerDate = NSDate()
        delegate?.audioModule.play()
        timer = NSTimer.scheduledTimerWithTimeInterval(0.5, target: self, selector: #selector(updateValuesSafe), userInfo: nil, repeats: true)
    }
    
    func seek(frac: Double) {
        delegate?.audioModule.seek(frac)
    }
    
    func skip() {
        self.currentTrack?.is_playing = false
        timer?.invalidate()
        delegate?.audioModule.skip()
    }
    
    func skipBackward() {
        self.currentTrack?.is_playing = false
        timer?.invalidate()
        delegate?.audioModule.skip_backward()
    }
    
    
    @IBAction func playPressed(sender: AnyObject) {
        print("called")
        if (paused == true) {
            //if not initialized, play selected track/shuffle
            unpause()
            paused = false
        }
        else {
            pause()
            paused = true
        }
    }
    
    @IBAction func toggleFilterVisibility(sender: AnyObject) {
        if librarySplitView.arrangedSubviews.contains(advancedFilterViewController!.view) {
            print("library split view does indeed contain advanced filter")
            librarySplitView.removeArrangedSubview(advancedFilterViewController!.view)
        } else {
            librarySplitView.insertArrangedSubview(advancedFilterViewController!.view, atIndex: 0)
        }
    }
    
    func initializeInterfaceForNetworkTrack() {
        theBox.contentView?.hidden = false
        print("initializing interface for network track")
        self.progressBar.indeterminate = true
        self.progressBar.startAnimation(nil)
        self.songNameLabel.stringValue = "Initializing playback..."
        self.artistAlbumLabel.stringValue = ""
        self.durationLabel.stringValue = ""
        self.currentTimeLabel.stringValue = ""
    }
    
    func initializeInterfaceForNewTrack() {
        print("paused value in mwc is \(paused)")
        if self.progressBar.indeterminate == true {
            self.progressBar.stopAnimation(nil)
            self.progressBar.indeterminate = false
        }
        var aa_string = ""
        var name_string = ""
        let the_track = self.currentTrack!
        albumArtViewController?.initAlbumArt(the_track)
        name_string = the_track.name!
        if the_track.artist != nil {
            aa_string += (the_track.artist! as Artist).name!
            if the_track.album != nil {
                aa_string += (" - " + (the_track.album! as Album).name!)
            }
        }
        timer?.invalidate()
        theBox.contentView!.hidden = false
        songNameLabel.stringValue = name_string
        artistAlbumLabel.stringValue = aa_string
        duration = delegate?.audioModule.duration_seconds
        durationLabel.stringValue = getTimeAsString(duration!)!
        currentTimeLabel.stringValue = getTimeAsString(0)!
        lastTimerDate = NSDate()
        secsPlayed = 0
        progressBar.hidden = false
        progressBar.doubleValue = 0
        startTimer()
    }

    func startTimer() {
        //timer = NSTimer.scheduledTimerWithTimeInterval(0.5, target: self, selector: #selector(updateValuesUnsafe), userInfo: nil, repeats: true)
        timer = NSTimer.scheduledTimerWithTimeInterval(0.5, target: self, selector: #selector(updateValuesSafe), userInfo: nil, repeats: true)
        NSRunLoop.currentRunLoop().addTimer(timer!, forMode: NSRunLoopCommonModes)
    }
    
    func updateValuesUnsafe() {
        print("unsafe called")
        let nodeTime = delegate?.audioModule.curNode.lastRenderTime
        let playerTime = delegate?.audioModule.curNode.playerTimeForNodeTime(nodeTime!)
        print("unsafe update times")
        print(nodeTime)
        print(playerTime)
        var offset_thing: Double?
        if delegate?.audioModule.track_frame_offset == nil {
            offset_thing = 0
        }
        else {
            offset_thing  = delegate?.audioModule.track_frame_offset!
            print(offset_thing)
        }
        print(delegate?.audioModule.total_offset_seconds)
        print(delegate?.audioModule.total_offset_frames)
        let seconds = ((Double((playerTime?.sampleTime)!) + offset_thing!) / (playerTime?.sampleRate)!) - Double(delegate!.audioModule.total_offset_seconds)
        let seconds_string = getTimeAsString(seconds)
        if (timer?.valid == true) {
            print("within valid clause")
            currentTimeLabel.stringValue = seconds_string!
            print(seconds_string)
            progressBar.doubleValue = (seconds * 100) / duration!
        }
        else {
            currentTimeLabel.stringValue = ""
            progressBar.doubleValue = 0
        }
        secsPlayed = seconds
        lastTimerDate = NSDate()
    }
    
    func updateValuesSafe() {
        let lastUpdateTime = lastTimerDate
        let currentTime = NSDate()
        let updateQuantity = currentTime.timeIntervalSinceDate(lastUpdateTime!)
        secsPlayed += updateQuantity
        let seconds_string = getTimeAsString(secsPlayed)
        if timer?.valid == true {
            currentTimeLabel.stringValue = seconds_string!
            progressBar.doubleValue = (secsPlayed * 100) / duration!
            progressBar.displayIfNeeded()
            lastTimerDate = currentTime
        } else {
            timer?.invalidate()
            //print("doingle")
            //currentTimeLabel.stringValue = ""
            //progressBar.doubleValue = 0
        }
    }
    
    func cleanUpBar() {
        print("other doingle")
        theBox.contentView!.hidden = true
        songNameLabel.stringValue = ""
        artistAlbumLabel.stringValue = ""
        duration = 0
        durationLabel.stringValue = ""
        currentTimeLabel.stringValue = ""
        progressBar.doubleValue = 100
    }
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if context == &my_context {
            if keyPath! == "track_changed" {
                let before = NSDate()
                print("controller detects track change")
                currentTrack?.is_playing = false
                if trackQueue.count > 0 {
                    self.currentTrack = trackQueue.removeFirst()
                }
                timer?.invalidate()
                initializeInterfaceForNewTrack()
                currentTrack?.is_playing = true
                trackQueueViewController!.nextTrack()
                let after = NSDate()
                let since = after.timeIntervalSinceDate(before)
                print(since)
            }
            else if keyPath! == "done_playing" {
                print("controller detects finished playing")
                cleanUpBar()
            }
            else if keyPath! == "sortDescriptors" {
                if (currentSourceListItem == currentAudioSource) {
                    self.modifyPlayOrderForSortDescriptorChange()
                }
            }
            else if keyPath! == "filterPredicate" {
                print("filter predicate changed")
                if (currentSourceListItem == currentAudioSource) && current_source_play_order != nil {
                    self.current_source_play_order = currentTableViewController!.fixPlayOrderForChangedFilterPredicate(current_source_play_order!, shuffleState: shuffleButton.state)
                }
                print(current_source_play_order?.count)
                print(current_source_temp_shuffle?.count)
                //updateCachedSorts()
                //updateNewCachedSorts()
            } else if keyPath! == "arrangedObjects" {
                updateInfo()
            }
        }
    }
    
    func updateInfo() {
        print("updateinfo called")
        if self.currentTableViewController == nil {
            return
        }
        dispatch_async(dispatch_get_main_queue()) {
            let trackArray = (self.currentTableViewController?.trackViewArrayController?.arrangedObjects as! [TrackView])
            let numItems = trackArray.count
            let totalSize = trackArray.map({return (($0.track)!.size!.longLongValue)}).reduce(0, combine: {$0 + $1})
            let totalTime = trackArray.map({return ($0.track)!.time!.doubleValue}).reduce(0, combine: {$0 + $1})
            let numString = self.numberFormatter.stringFromNumber(numItems)
            let sizeString = self.sizeFormatter.stringFromByteCount(totalSize)
            let timeString = self.dateFormatter.stringFromTimeInterval(totalTime/1000)
            dispatch_async(dispatch_get_main_queue()) {
                self.infoString = "\(numString!) items; \(timeString!); \(sizeString)"
                self.infoField.stringValue = self.self.infoString!
            }
        }
    }
    
    @IBAction func trackListTriangleClicked(sender: AnyObject) {
        print("break")
    }
    
    //mark album art
    
    override func windowDidLoad() {
        let sourceListView = SourceListViewController(nibName: "SourceListViewController", bundle: nil)
        sourceListTargetView.addSubview(sourceListView!.view)
        numberFormatter.numberStyle = NSNumberFormatterStyle.DecimalStyle
        dateFormatter.unitsStyle = NSDateComponentsFormatterUnitsStyle.Full
        print(hasMusic)
        self.delegate!.audioModule.mainWindowController = self
        progressBar.displayedWhenStopped = true
        progressBarView.progressBar = progressBar
        progressBarView.mainWindowController = self
        theBox.contentView?.hidden = true
        searchField.delegate = self
                self.currentTableViewController = libraryTableViewController
        self.delegate?.audioModule.addObserver(self, forKeyPath: "track_changed", options: .New, context: &my_context)
        self.delegate?.audioModule.addObserver(self, forKeyPath: "done_playing", options: .New, context: &my_context)
        self.libraryTableViewController?.trackViewArrayController.addObserver(self, forKeyPath: "arrangedObjects", options: .New, context: &my_context)
        self.libraryTableViewController?.trackViewArrayController.addObserver(self, forKeyPath: "filterPredicate", options: .New, context: &my_context)
        trackQueueViewController?.mainWindowController = self
        volumeSlider.continuous = true
        self.window!.titleVisibility = NSWindowTitleVisibility.Hidden
        self.window!.titlebarAppearsTransparent = true
        NSUserDefaults.standardUserDefaults().setBool(true, forKey: "checkEmbeddedArtwork")
        current_source_play_order = (libraryTableViewController!.trackViewArrayController.arrangedObjects as! [TrackView]).map( {return $0.track!.id as! Int})
        super.windowDidLoad()
    }
}
