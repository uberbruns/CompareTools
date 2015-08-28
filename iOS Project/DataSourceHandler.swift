//
//  DataSourceHandler.swift
//
//  Created by Karsten Bruns on 27/08/15.
//  Copyright © 2015 bruns.me. All rights reserved.
//

import Foundation


public class DataSourceHandler {
    
    public typealias ItemUpdateHandler = (items: [Comparable], section: Int, insertIndexPaths: [NSIndexPath], reloadIndexPaths: [NSIndexPath], deleteIndexPaths: [NSIndexPath]) -> ()
    public typealias ItemReorderHandler = (items: [Comparable], section: Int, reorderMap: [Int:Int]) -> ()
    public typealias SectionUpdateHandler = (sections: [ComparableSection], insertIndexSet: NSIndexSet, reloadIndexSet: NSIndexSet, deleteIndexSet: NSIndexSet) -> ()
    public typealias SectionReorderHandler = (sections: [ComparableSection], reorderMap: [Int:Int]) -> ()
    public typealias StartHandler = () -> ()
    public typealias CompletionHandler = () -> ()
    
    public var itemUpdate: ItemUpdateHandler? = nil
    public var itemReorder: ItemReorderHandler? = nil
    public var sectionUpdate: SectionUpdateHandler? = nil
    var sectionReorder: SectionReorderHandler? = nil
    
    public var start: StartHandler? = nil
    public var completion: CompletionHandler? = nil
    
    private var isDiffing: Bool = false
    
    
    public func queueComparison(oldSections oldSections: [ComparableSection], newSections: [ComparableSection]) -> Bool
    {
        guard isDiffing == false else { return false }
        isDiffing = true
        
        diff(oldSections: oldSections, newSections: newSections)
        return true
    }
    
    
    private func diff(oldSections oldSections: [ComparableSection], newSections: [ComparableSection])
    {
        let mainQueue = dispatch_get_main_queue()
        let backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)
        
        dispatch_async(backgroundQueue) {
            
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
            
            dispatch_async(mainQueue) {
                
                self.start?()
                
                for (oldSectionIndex, itemDiff) in itemDiffs.sort({ $0.0 < $1.0 }) {
                    
                    // Create index paths
                    let insertIndexPaths = itemDiff.insertionSet.map({ index in NSIndexPath(forRow: index, inSection: oldSectionIndex)})
                    let reloadIndexPaths = itemDiff.reloadSet.map({ index in NSIndexPath(forRow: index, inSection: oldSectionIndex)})
                    let deleteIndexPaths = itemDiff.deletionSet.map({ index in NSIndexPath(forRow: index, inSection: oldSectionIndex)})
                    
                    // Call item handler functions
                    self.itemUpdate?(items: itemDiff.unmovedItems, section: oldSectionIndex, insertIndexPaths: insertIndexPaths, reloadIndexPaths: reloadIndexPaths, deleteIndexPaths: deleteIndexPaths)
                    self.itemReorder?(items: itemDiff.newItems, section: oldSectionIndex, reorderMap: itemDiff.moveSet)
                    
                }
                
                let sectionDiff = ComparisonTool.diff(old: oldSections.map({$0}), new: newSections.map({$0}))
                
                // Change type
                let updateItems = sectionDiff.unmovedItems.flatMap({ $0 as? ComparableSection })
                let reorderItems = sectionDiff.newItems.flatMap({ $0 as? ComparableSection })
                
                // Call section handler functions
                self.sectionUpdate?(sections: updateItems, insertIndexSet: sectionDiff.insertionSet, reloadIndexSet: sectionDiff.reloadSet, deleteIndexSet: sectionDiff.deletionSet)
                self.sectionReorder?(sections: reorderItems, reorderMap: sectionDiff.moveSet)
                
                self.completion?()
                self.isDiffing = false
            }
            
        }
        
    }
    
}