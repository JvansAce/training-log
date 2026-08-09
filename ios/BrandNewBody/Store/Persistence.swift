import Foundation
import SwiftData

/// Builds the model container, and decides what happens when iCloud isn't
/// available.
///
/// The CloudKit mirror is a *configuration*, not a code path: one
/// `cloudKitDatabase: .automatic` and SwiftData syncs every model in the
/// schema to the user's private database, encrypted in transit, backed up with
/// their account, and shared across their devices. There is no sync code in
/// this app because there is no sync code to write.
///
/// What it does need is a fallback. A container that can't reach CloudKit —
/// no iCloud account on the device, the entitlement missing from a
/// development build, storage full — must not stop the app opening in a gym.
/// So a failure drops to a local-only store and Setup says so plainly, rather
/// than pretending the log is backed up when it isn't.
enum Persistence {

    struct Result {
        var container: ModelContainer
        var status: AppStore.CloudStatus
    }

    /// Named so the on-disk store is stable across launches. Changing this
    /// string orphans everyone's data — it is not a display name.
    static let storeName = "BrandNewBody"

    @MainActor
    static func makeContainer() -> Result {
        let schema = Schema(SchemaV1.models)

        do {
            let cloud = ModelConfiguration(storeName, schema: schema,
                                           isStoredInMemoryOnly: false,
                                           cloudKitDatabase: .automatic)
            let container = try ModelContainer(for: schema, configurations: [cloud])
            return Result(container: container, status: .syncing)
        } catch {
            let cloudError = error
            do {
                let local = ModelConfiguration(storeName, schema: schema,
                                               isStoredInMemoryOnly: false,
                                               cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, configurations: [local])
                return Result(container: container,
                              status: .localOnly(reason: cloudError.localizedDescription))
            } catch {
                // Both on-disk attempts failed, which in practice means the
                // store file is unreadable. An in-memory container at least
                // opens the app and lets the user export whatever arrives from
                // iCloud, instead of crashing on launch forever.
                let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                // If even this fails the process cannot continue, and a clear
                // trap beats an optional threaded through the whole app for a
                // case that means the device itself is broken.
                guard let container = try? ModelContainer(for: schema, configurations: [memory]) else {
                    fatalError("Could not open any model container: \(error)")
                }
                return Result(container: container,
                              status: .localOnly(reason: "The local database could not be opened. Nothing typed in this session will be saved."))
            }
        }
    }
}
