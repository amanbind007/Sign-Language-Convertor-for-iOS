//
//  Predictor.swift
//  Sign Lang Translator iOS
//
//  Created by Aman Bind on 04/11/22.
//

import Foundation
import Vision

typealias HandSignClassifier = HandSignClassifier_ver0_1

protocol PredictorDelegate: AnyObject{
    func predictor(_ predictor: Predictor, didFindNewRecognizedPoints points: [CGPoint])
    func predictor(_ predictor: Predictor, didLabelAction action : String, with confidence: Double)
}

class Predictor {
    
    weak var delegate: PredictorDelegate?
    
    let predictionWindowSize = 60
    var posesWindow : [VNHumanHandPoseObservation] = []
    
    init(){
        posesWindow.reserveCapacity(predictionWindowSize)
    }
    
    func estimation(sampleBuffer: CMSampleBuffer){
        
        let requestHandler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        
        
        let request = VNDetectHumanHandPoseRequest(completionHandler: handPoseHandler)
        
        do{
            try requestHandler.perform([request])
        }catch{
            print("Unable to perform the request, with error: \(error)")
        }
    }

    func handPoseHandler(request:VNRequest, error: Error?){
        guard let observations = request.results as? [VNHumanHandPoseObservation] else {return}
        
        observations.forEach{
            processObservation($0)
        }
        
        if let result = observations.first{
            storeObservation(result)
            
            labelActionType()
        }
    }
    
    func labelActionType(){
        guard let handSignClassifier = try? HandSignClassifier(configuration: MLModelConfiguration()),
              let poseMultiArray = prepareInputWithObservations(posesWindow),
              let predictions = try? handSignClassifier.prediction(poses: poseMultiArray) else { return }
        
        let label = predictions.label
        let confidence = predictions.labelProbabilities[label] ?? 0
        
        delegate?.predictor(self, didLabelAction: label, with: confidence)
    }
    
    func prepareInputWithObservations(_ observations: [VNHumanHandPoseObservation]) -> MLMultiArray?{
        let numAvailableFrames = observations.count
        let observationsNeeded = 60
        var multiArrayBuffer = [MLMultiArray]()
        
        for frameIndex in 0 ..< min(numAvailableFrames, observationsNeeded){
            let pose = observations[frameIndex]
            
            do{
                let oneFrameMultiArray = try pose.keypointsMultiArray()
                multiArrayBuffer.append(oneFrameMultiArray)
            }
            catch{
                continue
            }
        }
        
        if numAvailableFrames < observationsNeeded {
            for _ in 0 ..< (observationsNeeded-numAvailableFrames){
                do {
                    let oneFrameMultiArray = try MLMultiArray(shape: [1,3,21], dataType: .float32)
                    try resetMultiArray(oneFrameMultiArray)
                    multiArrayBuffer.append(oneFrameMultiArray)
                }
                catch{
                    continue
                }
            }
        }
        return MLMultiArray(concatenating: [MLMultiArray](multiArrayBuffer), axis: 0, dataType: .float32)
    }
    
    func resetMultiArray(_ predictionWindow: MLMultiArray, with value: Double = 0.0) throws{
        let pointer = try UnsafeMutableBufferPointer<Double>(predictionWindow)
        pointer.initialize(repeating: value)
    }
    
    func storeObservation(_ obseravtion: VNHumanHandPoseObservation){
        
        if posesWindow.count >= predictionWindowSize{
            posesWindow.removeFirst()
        }
        
        posesWindow.append(obseravtion)
        
    }
    
    func processObservation(_ observation: VNHumanHandPoseObservation){
        do{
            let recognizedPoints = try observation.recognizedPoints(forGroupKey: .all)
            
            var displayedPoints = recognizedPoints.map{
                CGPoint(x: $0.value.x, y: 1-$0.value.y)
            }
            
            delegate?.predictor(self, didFindNewRecognizedPoints: displayedPoints)
        }
        catch{
            print("Error finding recognizedPoints")
        }
    }
    
}
