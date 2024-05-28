//
//  ImageOperations.swift
//  ImageOperationPOC
//
//  Created by Tin Le on 28/05/2024.
//

import UIKit

enum ImageRecordState {
    case new, downloaded, filtered, failed
}

struct CodableImageRecord: Codable {
    let title: String
    let url: String
}

class ImageRecord {
    let name: String
    let url: URL
    var state = ImageRecordState.new
    var image = UIImage(named: "Placeholder")
    
    init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

class PendingOperations {
    lazy var downloadsInProgress: [IndexPath: Operation] = [:]
    lazy var downloadQueue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Download image queue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    lazy var filtrationsInProgress: [IndexPath: Operation] = [:]
    lazy var filtrationQueue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Filtration image queue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
}

class ImageDownloader: Operation {
    let imageRecord: ImageRecord
    
    init(imageRecord: ImageRecord) {
        self.imageRecord = imageRecord
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        guard let imageData = try? Data(contentsOf: imageRecord.url) else {
            return
        }
        
        guard !isCancelled else { return }
        
        guard !imageData.isEmpty else {
            imageRecord.image = UIImage(named: "Failed")
            imageRecord.state = .failed
            return
        }
        
        imageRecord.image = UIImage(data: imageData)
        imageRecord.state = .downloaded
    }
}

class ImageFiltration: Operation {
    let imageRecord: ImageRecord
    
    init(imageRecord: ImageRecord) {
        self.imageRecord = imageRecord
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        guard imageRecord.state == .downloaded else {
            return
        }
        
        if let image = imageRecord.image,
           let filteredImage = applySepiaFilter(image) {
            imageRecord.image = filteredImage
            imageRecord.state = .filtered
        }
    }
    
    func applySepiaFilter(_ image: UIImage) -> UIImage? {
        guard let data = image.pngData() else { return nil }
        let inputImage = CIImage(data: data)
        
        if isCancelled {
            return nil
        }
        
        let context = CIContext(options: nil)
        
        guard let filter = CIFilter(name: "CISepiaTone") else { return nil }
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(0.8, forKey: "inputIntensity")
        
        if self.isCancelled {
            return nil
        }
        
        guard
            let outputImage = filter.outputImage,
            let outImage = context.createCGImage(outputImage, from: outputImage.extent)
        else {
            return nil
        }
        
        return UIImage(cgImage: outImage)
    }
}
