//
//  DataSourceHandler.swift
//
//  Created by Karsten Bruns on 27/08/15.
//  Copyright © 2015 bruns.me. All rights reserved.
//

import Foundation


public class DataSourceHandler {
    
    public typealias ItemUpdateHandler = (items: [ComparableItem], section: Int, insertIndexPaths: [NSIndexPath], reloadIndexPaths: [NSIndexPath], deleteIndexPaths: [NSIndexPath]) -> ()
    public typealias ItemReorderHandler = (items: [ComparableItem], section: Int, reorderMap: [Int:Int]) -> ()
    public typealias SectionUpdateHandler = (sections: [ComparableSectionItem], insertIndexSet: NSIndexSet, reloadIndexSet: NSIndexSet, deleteIndexSet: NSIndexSet) -> ()
    public typealias SectionReorderHandler = (sections: [ComparableSectionItem], reorderMap: [Int:Int]) -> ()
    public typealias StartHandler = () -> ()
    public typealias CompletionHandler = () -> ()
    
    public var userInterfaceUpdateTime: Double = 0.2
    
    // Update handler
    public var itemUpdate: ItemUpdateHandler? = nil
    public var itemReorder: ItemReorderHandler? = nil
    public var sectionUpdate: SectionUpdateHandler? = nil
    public var sectionReorder: SectionReorderHandler? = nil
    
    public var start: StartHandler? = nil
    public var completion: CompletionHandler? = nil
    
    // State vars to mind the background operation
    private var isDiffing: Bool = false
    private var resultIsOutOfDate: Bool = false
    
    // State var to mind the UI update
    private var timeLockEnabled: Bool = false
    private var lastUpdateTime: NSDate = NSDate(timeIntervalSince1970: 0)
    
    // Section data
    private var oldSections: [ComparableSectionItem]? = nil
    private var newSections: [ComparableSectionItem]? = nil
    
    
    public func queueComparison(oldSections oldSections: [ComparableSectionItem], newSections: [ComparableSectionItem])
    {
        // Set Sections
        if self.oldSections == nil {
            // Old section should change only when diff(completes)
            self.oldSections = oldSections
        }
        
        // New section are always defined
        self.newSections = newSections
        
        // Guarding
        if isDiffing == true {
            // We declare the current result as out-of-date
            // because more recent 'newSections' are available
            self.resultIsOutOfDate = true
            return
        }
        
        diff()
    }
    
    
    private func diff()
    {
        // Guarding
        guard let oldSections = self.oldSections else { return }
        guard let newSections = self.newSections else { return }
        
        // Set State
        self.isDiffing = true
        
        // From now on the diff function considers 'newSections' not out-of-date
        self.resultIsOutOfDate = false

        // We do the diffing on a background thread
        let backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)

        dispatch_async(backgroundQueue) {
            
            // Diffing Items
            var itemDiffs = [Int: ComparisonResult]()
            for (oldSectionIndex, oldSection) in oldSections.enumerate() {
                
                let newIndex = newSections.indexOf({ newSection -> Bool in
                    let comparisonLevel = newSection.compareTo(oldSection)
                    return comparisonLevel.hasSameIdentifier
                })
                
                if let newIndex = newIndex {
                    // Diffing
                    let oldItems = oldSection.items
                    let newItems = newSections[newIndex].items
                    let itemDiff = ComparisonTool.diff(old: oldItems, new: newItems)
                    itemDiffs[oldSectionIndex] = itemDiff
                }
                
            }
            
            // "Changing" type to 'ComparableItem'
            // Like 'as' suggest this change in type always succeeds
            // We do it to satisfy the argument requirements of ComparisonTool.diff()
            let oldSectionAsItems = oldSections.map({ $0 as ComparableItem })
            let newSectionsAsItems = newSections.map({ $0 as ComparableItem })
            
            // Diffing sections
            let sectionDiff = ComparisonTool.diff(old: oldSectionAsItems, new: newSectionsAsItems)
            
            // Diffing is done
            // We do the the UI updates on the main thread
            let mainQueue = dispatch_get_main_queue()
            dispatch_async(mainQueue) {
                
                // A few guards...
                
                if self.resultIsOutOfDate == true {
                    // In the meantime 'newResults' came in, this means
                    // a new diff() and we are stopping the update
                    self.diff()
                    return
                }
                
                if self.timeLockEnabled == true {
                    // There is already a future diff() scheduled
                    // we are stopping here
                    return
                }
                
                let updateAllowedIn = self.lastUpdateTime.timeIntervalSinceNow + self.userInterfaceUpdateTime
                if  updateAllowedIn > 0 {
                    // updateAllowedIn > 0 means the allowed update time is in the future
                    // so we schedule a new diff() for this point in time
                    self.timeLockEnabled = true
                    DataSourceHandler.executeDelayed(updateAllowedIn) {
                        self.timeLockEnabled = false
                        self.diff()
                    }
                    return
                }
                
                // Okay, we are passed the guards lets start by calling the start handler function
                self.start?()
                
                // We do the item update for the old section order, because the sections
                // are not moved yet
                for (oldSectionIndex, itemDiff) in itemDiffs.sort({ $0.0 < $1.0 }) {
                    
                    // Create index paths
                    let insertIndexPaths = itemDiff.insertionSet.map({ index in NSIndexPath(forRow: index, inSection: oldSectionIndex)})
                    let reloadIndexPaths = itemDiff.reloadSet.map({ index in NSIndexPath(forRow: index, inSection: oldSectionIndex)})
                    let deleteIndexPaths = itemDiff.deletionSet.map({ index in NSIndexPath(forRow: index, inSection: oldSectionIndex)})
                    
                    // Call item handler functions
                    self.itemUpdate?(items: itemDiff.unmovedItems, section: oldSectionIndex, insertIndexPaths: insertIndexPaths, reloadIndexPaths: reloadIndexPaths, deleteIndexPaths: deleteIndexPaths)
                    self.itemReorder?(items: itemDiff.newItems, section: oldSectionIndex, reorderMap: itemDiff.moveSet)
                    
                }
                
                // Change type from ComparableItem to ComparableSectionItem.
                // Since this is expected to succeed and we could not recover,
                // so a force unwrap is justified
                let updateItems = sectionDiff.unmovedItems.map({ $0 as! ComparableSectionItem })
                let reorderItems = sectionDiff.newItems.map({ $0 as! ComparableSectionItem })
                
                // Call section handler functions
                self.sectionUpdate?(sections: updateItems, insertIndexSet: sectionDiff.insertionSet, reloadIndexSet: sectionDiff.reloadSet, deleteIndexSet: sectionDiff.deletionSet)
                self.sectionReorder?(sections: reorderItems, reorderMap: sectionDiff.moveSet)
                
                // Call completion block
                self.completion?()
                
                // Reset state
                self.lastUpdateTime = NSDate()
                self.oldSections = nil
                self.newSections = nil
                self.isDiffing = false
            }
            
        }
        
    }
    
    
    static private func executeDelayed(time: Int, action: () -> ())
    {
        self.executeDelayed(Double(time), action: action)
    }
    
    
    static private func executeDelayed(time: Double, action: () -> ())
    {
        if time == 0 {
            action()
            return
        }
        
        let nanoSeconds: Int64 = Int64(Double(NSEC_PER_SEC) * time);
        let when = dispatch_time(DISPATCH_TIME_NOW, nanoSeconds)
        dispatch_after(when, dispatch_get_main_queue(), {
            action()
        });
    }
    
}