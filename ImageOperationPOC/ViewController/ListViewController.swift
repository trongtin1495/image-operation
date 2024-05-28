//
//  ListViewController.swift
//  ImageOperationPOC
//
//  Created by Tin Le on 28/05/2024.
//

import UIKit

class ListViewController: UITableViewController {
    
    var images: [ImageRecord] = []
    let pendingOperations = PendingOperations()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Image Operation"
        fetchImageDetails()
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return images.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ImageCell", for: indexPath)
        
        if cell.accessoryView == nil {
            let indicator = UIActivityIndicatorView(style: UIActivityIndicatorView.Style.medium)
            cell.accessoryView = indicator
        }
        
        let indicator = cell.accessoryView as! UIActivityIndicatorView
        let imageDetails = images[indexPath.row]
        
        cell.textLabel?.text = imageDetails.name
        cell.imageView?.image = imageDetails.image
        
        switch imageDetails.state {
        case .filtered:
            indicator.stopAnimating()
            
        case .failed:
            indicator.stopAnimating()
            cell.textLabel?.text = "Load failed!"
        case .new, .downloaded:
            indicator.startAnimating()
            if !tableView.isDragging && !tableView.isDecelerating {
                startOperation(for: imageDetails, at: indexPath)
            }
        }
        
        return cell
    }
}

// MARK: - Helpers
private extension ListViewController {
    func createAlert(message: String = "There was an error fetching image details") -> UIAlertController {
        let alertController = UIAlertController(title: "Oops!", message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .default)
        alertController.addAction(okAction)
        
        return alertController
    }
    
    func fetchImageDetails() {
        guard let url = URL(string: "https://jsonplaceholder.typicode.com/photos") else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.present(self.createAlert(message: "Invalid URL"), animated: true, completion: nil)
            }
            return
        }
        
        let task: URLSessionDataTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.present(self.createAlert(message: error.localizedDescription), animated: true, completion: nil)
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.present(self.createAlert(message: "No data"), animated: true, completion: nil)
                }
                return
            }
            
            do {
                let photos: [CodableImageRecord] = try JSONDecoder().decode([CodableImageRecord].self, from: data)
                for photo in photos {
                    let imageURL = URL(string: photo.url)!
                    let imageRecord = ImageRecord(name: photo.title, url: imageURL)
                    self?.images.append(imageRecord)
                }
                
                DispatchQueue.main.async {
                    self?.tableView.reloadData()
                }
                
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.present(self.createAlert(message: error.localizedDescription), animated: true, completion: nil)
                }
            }
        }
        
        task.resume()
    }
}

// MARK: - scrollview delegate methods
extension ListViewController {
    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        suspendAllOperations()
    }
    
    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            loadImagesForVisibleCells()
            resumeAllOperations()
        }
    }
    
    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        loadImagesForVisibleCells()
        resumeAllOperations()
    }
}

// MARK: - Operation management
private extension ListViewController {
    func startOperation(for imageRecord: ImageRecord, at indexPath: IndexPath) {
        switch imageRecord.state {
        case .new:
            startDownload(for: imageRecord, at: indexPath)
        case .downloaded:
            startFiltration(for: imageRecord, at: indexPath)
        default:
            print("[tinlog] do nothing")
        }
    }
    
    func startDownload(for imageRecord: ImageRecord, at indexPath: IndexPath) {
        guard pendingOperations.downloadsInProgress[indexPath] == nil else {
            return
        }
        
        let downloader = ImageDownloader(imageRecord: imageRecord)
        downloader.completionBlock = { [weak self] in
            guard !downloader.isCancelled else { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.pendingOperations.downloadsInProgress.removeValue(forKey: indexPath)
                self?.tableView.reloadRows(at: [indexPath], with: .fade)
            }
        }
        
        pendingOperations.downloadsInProgress[indexPath] = downloader
        pendingOperations.downloadQueue.addOperation(downloader)
    }
    
    func startFiltration(for imageRecord: ImageRecord, at indexPath: IndexPath) {
        guard pendingOperations.filtrationsInProgress[indexPath] == nil else {
            return
        }
        
        let filterer = ImageFiltration(imageRecord: imageRecord)
        filterer.completionBlock = { [weak self] in
            guard !filterer.isCancelled else { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.pendingOperations.filtrationsInProgress.removeValue(forKey: indexPath)
                self?.tableView.reloadRows(at: [indexPath], with: .fade)
            }
        }
        
        pendingOperations.filtrationsInProgress[indexPath] = filterer
        pendingOperations.filtrationQueue.addOperation(filterer)
    }
    
    func suspendAllOperations() {
        pendingOperations.downloadQueue.isSuspended = true
        pendingOperations.filtrationQueue.isSuspended = true
    }
    
    func resumeAllOperations() {
        pendingOperations.downloadQueue.isSuspended = false
        pendingOperations.filtrationQueue.isSuspended = false
    }
    
    func loadImagesForVisibleCells() {
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows else {
            return
        }
        
        var allPendingOperations = Set(pendingOperations.downloadsInProgress.keys)
        allPendingOperations.formUnion(pendingOperations.filtrationsInProgress.keys)
        
        var tobeCancelled = allPendingOperations
        let visiblePathsSet = Set(visibleIndexPaths)
        tobeCancelled.subtract(visiblePathsSet)
        
        var tobeStarted = visiblePathsSet
        tobeStarted.subtract(allPendingOperations)
        
        for indexPath in tobeCancelled {
            if let pendingDownload = pendingOperations.downloadsInProgress[indexPath] {
                pendingDownload.cancel()
            }
            
            pendingOperations.downloadsInProgress.removeValue(forKey: indexPath)
            if let pendingFiltration = pendingOperations.filtrationsInProgress[indexPath] {
                pendingFiltration.cancel()
            }
            
            pendingOperations.filtrationsInProgress.removeValue(forKey: indexPath)
        }
        
        for indexPath in tobeStarted {
            let recordToProcess = images[indexPath.row]
            startOperation(for: recordToProcess, at: indexPath)
        }
    }
}
