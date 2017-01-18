import Alamofire
import Crust
import Foundation
import JSONValueRX

class ResponseHandler {
    
    private let queue: OperationQueue
    private let callbackQueue: OperationQueue
    
    init(queue: OperationQueue = OperationQueue(),
         callbackQueue: OperationQueue = OperationQueue.main) {
        
        self.queue = queue
        self.callbackQueue = callbackQueue
    }
    
    func handle<Mapping: Crust.Mapping>(response: DataResponse<Any>, mapping: @escaping () -> Mapping, completion: @escaping RequestCompletion<Mapping>) {
        
        do {
            let value: Any = try {
                switch response.result {
                case .success(let value):
                    return value
                    
                case .failure(let e):
                    
                    let gqlError: AutoGraphError? = {
                        guard let value = Alamofire.Request.serializeResponseJSON(
                            options: .allowFragments,
                            response: response.response,
                            data: response.data, error: nil).value,
                            let json = try? JSONValue(object: value) else {
                                
                                return nil
                        }
                        
                        return AutoGraphError(graphQLResponseJSON: json)
                    }()
                    
                    throw AutoGraphError.network(error: e, underlying: gqlError)
                }
            }()
            
            let json = try JSONValue(object: value)
            
            if let queryError = AutoGraphError(graphQLResponseJSON: json) {
                throw queryError
            }
            
            self.queue.addOperation { [weak self] in
                self?.map(json: json, mapping: mapping, completion: completion)
            }
        }
        catch let e {
            self.fail(error: e, mapping: mapping, completion: completion)
        }
    }
    
    private func map<Mapping: Crust.Mapping>(json: JSONValue, mapping: @escaping () -> Mapping, completion: @escaping RequestCompletion<Mapping>) {
        do {
            let mapper = Mapper<Mapping>()
            let result = try mapper.mapFromJSONToExistingObject(json, mapping: mapping())
            self.refetchAndComplete(result: result, json: json, mapping: mapping, completion: completion)
        }
        catch let e {
            self.fail(error: AutoGraphError.mapping(error: e), mapping: mapping, completion: completion)
        }
    }
    
    private func fail<Mapping: Crust.Mapping>(error: Error, mapping: () -> Mapping, completion: @escaping RequestCompletion<Mapping>) {
        self.callbackQueue.addOperation {
            completion(.failure(error))
        }
    }
    
    private func refetchAndComplete<Mapping: Crust.Mapping, MappedObject: Sequence>
        (result: MappedObject,
         json: JSONValue,
         mapping: @escaping () -> Mapping,
         completion: @escaping RequestCompletion<Mapping>)
        where Mapping.MappedObject == MappedObject, MappedObject.Iterator.Element: ThreadUnsafe {
            
            let primaryKey = MappedObject.Iterator.Element.primaryKey
            let primaryKeys: [[String : CVarArg]] = result.flatMap {
                guard case let value as CVarArg = $0.value(forKeyPath: primaryKey) else {
                    return nil
                }
                return [primaryKey : value]
            }
            
            self.callbackQueue.addOperation {
                let map = mapping()
                let results = map.adaptor.fetchObjects(type: MappedObject.Iterator.Element.self, primaryKeyValues: primaryKeys, isMapping: false)
            }
    }
    
    private func refetchAndComplete<Mapping: Crust.Mapping, MappedObject: ThreadUnsafe>
        (result: MappedObject,
         json: JSONValue,
         mapping: @escaping () -> Mapping,
         completion: @escaping RequestCompletion<Mapping>)
        where Mapping.MappedObject == MappedObject {
            
            
    }
    
    private func refetchAndComplete<Mapping: Crust.Mapping>(result: Mapping.MappedObject, json: JSONValue, mapping: @escaping () -> Mapping, completion: @escaping RequestCompletion<Mapping>) {
        
        if case let results as Collection = result {
            
        }
        
        self.callbackQueue.addOperation {
            
            let map = mapping()
            
            guard map.primaryKeys != nil else {
                completion(.success(result))
                return
            }
            
            
            completion(.success(result))
        }
    }
}
