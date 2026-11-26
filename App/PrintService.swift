import Foundation
import UIKit

@MainActor final class PrintService: NSObject, UIPrintInteractionControllerDelegate {
    private var picker: UIPrinterPickerController?
    private var busy = false

    func choose(current: URL?, completion: @escaping (Result<UIPrinter?, Error>) -> Void) {
        let picker = UIPrinterPickerController(initiallySelectedPrinter: current.map { UIPrinter(url: $0) })
        self.picker = picker
        if !picker.present(animated: true, completionHandler: { [weak self] controller, selected, error in
            self?.picker = nil
            if let error { completion(.failure(error)) }
            else { completion(.success(selected ? controller.selectedPrinter : nil)) }
        }) {
            self.picker = nil
            completion(.failure(AlterEgoError.invalid("Unable to open the printer picker.")))
        }
    }

    func submit(card: URL, printerURL: URL, name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !busy else { completion(.failure(AlterEgoError.invalid("A print request is already active."))); return }
        guard UIPrintInteractionController.isPrintingAvailable, let image = UIImage(contentsOfFile: card.path) else {
            completion(.failure(AlterEgoError.invalid("Printing is unavailable or the card cannot be loaded."))); return
        }
        busy = true
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .photo; info.jobName = name; info.orientation = .portrait
        controller.printInfo = info
        controller.delegate = self
        controller.printingItem = image
        controller.showsNumberOfCopies = false
        var finished = false
        func finish(_ result: Result<Void, Error>) {
            guard !finished else { return }; finished = true
            controller.printingItem = nil; controller.delegate = nil; self.busy = false
            completion(result)
        }
        let started = controller.print(to: UIPrinter(url: printerURL)) { _, completed, error in
            if let error { finish(.failure(error)) }
            else if completed { finish(.success(())) }
            else { finish(.failure(AlterEgoError.invalid("Print cancelled or not confirmed. Check the printer before retrying."))) }
        }
        if !started { finish(.failure(AlterEgoError.invalid("AirPrint could not start. Check Wi-Fi and printer."))) }
    }
    func printInteractionController(_ printInteractionController: UIPrintInteractionController, choosePaper paperList: [UIPrintPaper]) -> UIPrintPaper {
        UIPrintPaper.bestPaper(forPageSize: CGSize(width: CardRenderer.widthMM / 25.4 * 72, height: CardRenderer.heightMM / 25.4 * 72), withPapersFrom: paperList)
    }

    func calibrationCard() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alter-ego-calibration.jpg")
        let size = CGSize(width: CardRenderer.width, height: CardRenderer.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            for inset in [24.0, 60.0, 120.0] {
                UIColor.black.setStroke(); ctx.cgContext.setLineWidth(3)
                ctx.cgContext.stroke(CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset))
            }
            let colours: [UIColor] = [.red, .green, .blue, .cyan, .magenta, .yellow, .black]
            for (i, colour) in colours.enumerated() {
                colour.setFill(); ctx.fill(CGRect(x: 120 + CGFloat(i) * 137, y: 380, width: 137, height: 360))
            }
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 70, weight: .bold), .foregroundColor: UIColor.black, .paragraphStyle: style]
            ("ALTER EGO\n100 × 148 mm\nCalibration print" as NSString).draw(in: CGRect(x: 120, y: 850, width: 960, height: 480), withAttributes: attrs)
            ("Border marks: 2 / 5 / 10 mm" as NSString).draw(in: CGRect(x: 120, y: 1400, width: 960, height: 140), withAttributes: [.font: UIFont.systemFont(ofSize: 35), .foregroundColor: UIColor.black, .paragraphStyle: style])
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.94) else { throw AlterEgoError.invalid("Unable to create calibration image.") }
        try jpeg.write(to: url, options: .atomic); return url
    }
}
