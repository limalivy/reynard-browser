//
//  BrowserViewController+Downloads.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

extension BrowserViewController: DownloadsCoordinatorDelegate {
    @objc func pauseWebVideoForLocalPlayback() {
        tabManager.selectedTab?.session.mediaSession.pause()
    }

    var downloadsShouldRefreshLayoutForStoreChange: Bool {
        return !sidebarCoordinator.hostsSidebar
        && browserLayout.interfaceIdiom == .pad
        && browserLayout.chromeMode == .pad
    }
    
    func downloadsCoordinator(_ coordinator: DownloadsCoordinator, didUpdate summary: DownloadStoreSummary) {
        browserChrome.updateDownload(summary)
    }
    
    func downloadsCoordinatorDidRequestLayoutRefresh(_ coordinator: DownloadsCoordinator) {
        updateBrowserLayout(animated: false)
    }
}
