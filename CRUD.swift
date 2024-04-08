import Foundation

protocol DataTransformer {
    func encode<T: Encodable>(_ object: T) async throws -> Data
    func decode<T: Decodable>(data: Data) async throws -> T
}

class JSONDataTransformer: DataTransformer {
    func encode<T>(_ object: T) async throws -> Data where T : Encodable {
        let data = try JSONEncoder().encode(object)
        return data
    }

    func decode<T>(data: Data) async throws -> T where T : Decodable {
        let item: T = try JSONDecoder().decode(T.self, from: data)
        return item
    }
}

protocol CRUDRepository {
    typealias Item = Identifiable & Codable
    typealias ItemIdentifier = String

    associatedtype T: Item

    func create(_ item: T) async throws
    func read(id: ItemIdentifier) async throws -> T
    func update(_ item: T) async throws
    func delete(id: ItemIdentifier) async throws
}

struct CRUDRepositoryItem<T: Codable>: CRUDRepository.Item {
    let id: CRUDRepository.ItemIdentifier
    let value: T
}


enum CRUDRepositoryError: Error {
    case recordNotFound(id: AnyHashable)
}

extension String {
    func localized(comment: String? = nil) -> String {
        return NSLocalizedString(self, comment: comment ?? "")
    }
}

extension CRUDRepositoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .recordNotFound(let id):
            return "Record not found with ID: \(id.string)".localized()
        }
    }
}

struct Client: Codable {
    var name: String
}

extension Hashable {
    var string: String { String(describing: self) }
}

class UserDefaultsRepository<T: CRUDRepository.Item>: CRUDRepository {
    private typealias RecordIdentifier = String

    let tableName: String
    let dataTransformer: DataTransformer

    init(
        tableName: String,
        dataTransformer: DataTransformer
    ) {
        self.tableName = tableName
        self.dataTransformer = dataTransformer
    }

    private func key(id: CRUDRepository.ItemIdentifier) -> RecordIdentifier {
        "database_\(tableName)_item_\(id)"
    }

    private func key(item: T) -> RecordIdentifier {
        key(id: item.id.string)
    }

    private func isExists(id: CRUDRepository.ItemIdentifier) async throws -> Bool {
        UserDefaults.standard.data(forKey: key(id: id)) != nil
    }

    func create(_ item: T) async throws {
        let data = try await dataTransformer.encode(item)
        UserDefaults.standard.set(data, forKey: key(item: item))
        UserDefaults.standard.synchronize()
    }

    func read(id: CRUDRepository.ItemIdentifier) async throws -> T {
        guard let data = UserDefaults.standard.data(forKey: key(id: id)) else {
            throw CRUDRepositoryError.recordNotFound(id: id)
        }
        let item: T = try await dataTransformer.decode(data: data)
        return item
    }

    func update(_ item: T) async throws {
        let id = item.id.string
        guard try await isExists(id: id) else {
            throw CRUDRepositoryError.recordNotFound(id: id)
        }
        let data = try await dataTransformer.encode(item)
        UserDefaults.standard.set(data, forKey: key(item: item))
        UserDefaults.standard.synchronize()
    }

    func delete(id: ItemIdentifier) async throws {
        let key = key(id: id)
        guard try await isExists(id: key) else {
            throw CRUDRepositoryError.recordNotFound(id: id)
        }
        UserDefaults.standard.removeObject(forKey: id)
        UserDefaults.standard.synchronize()
    }
}

do {
    print("Value CRUD check")
    let repository = UserDefaultsRepository<CRUDRepositoryItem<Client>>(
        tableName: "Clients Database",
        dataTransformer: JSONDataTransformer()
    )

    let recordID = "Actor ID"
    try await repository.create(CRUDRepositoryItem(id: recordID, value: Client(name: "Steve Buscemi"))) // Create
    var value = try await repository.read(id: recordID).value // Read
    print(value.name)
    value.name = "Willem Dafoe"
    try await repository.update(CRUDRepositoryItem(id: recordID, value: value)) // Update
    let updatedValue = try await repository.read(id: recordID).value
    print(updatedValue.name)
    try await repository.delete(id: recordID)
    print("Deleted")
    let deletedValue = try await repository.read(id: recordID).value
    print(deletedValue.name)
}
catch {
    print(error.localizedDescription)
}

print("---")

do {
    print("Array CRUD check")
    let repository = UserDefaultsRepository<CRUDRepositoryItem<[Client]>>(
        tableName: "Clients Database",
        dataTransformer: JSONDataTransformer()
    )

    let recordID = "Actor ID"
    try await repository.create(CRUDRepositoryItem(id: recordID, value: [Client(name: "Steve Buscemi")])) // Create
    var value = try await repository.read(id: recordID).value.first! // Read
    print(value.name)
    value.name = "Willem Dafoe"
    try await repository.update(CRUDRepositoryItem(id: recordID, value: [value])) // Update
    let updatedValue = try await repository.read(id: recordID).value.first!
    print(updatedValue.name)
    try await repository.delete(id: recordID)
    print("Deleted")
    let deletedValue = try await repository.read(id: recordID).value.first!
    print(deletedValue.name)
}
catch {
    print(error.localizedDescription)
}

