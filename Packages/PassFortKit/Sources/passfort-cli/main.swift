import Foundation
import PassFortCrypto

let probe = Data("passfort seam check".utf8)
guard try echo(probe) == probe else {
    FileHandle.standardError.write(Data("seam round-trip MISMATCH\n".utf8))
    exit(1)
}
print("seam OK -- \(probe.count) bytes round-tripped through C++")
print("botan \(try botanVersion())")
