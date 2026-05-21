import XCTest
import SwiftData
@testable import MexicanTrain

final class SmokeTests: XCTestCase {
    @MainActor
    func testContainerInstantiates() throws {
        let schema = Schema([Game.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let game = Game()
        container.mainContext.insert(game)
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(FetchDescriptor<Game>())
        XCTAssertEqual(fetched.count, 1)
    }

    func testCabooseThemeIsCabooseColored() {
        let theme = Theme.caboose
        XCTAssertEqual(theme.buttonCornerRadius, 16)
        XCTAssertEqual(theme.displayFontName, "Rye-Regular")
    }
}
