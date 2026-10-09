import Foundation
import CheckKit
import FreeFanCore

let check = Checker("CoreCheck")
check.expect(false, "scaffold: CoreCheck not implemented yet")
exit(check.summary())
