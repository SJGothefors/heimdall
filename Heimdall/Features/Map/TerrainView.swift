import SceneKit
import SwiftUI

/// A real elevation mesh, projected in the same Web Mercator coordinates as 2D.
/// SceneKit is isolated here so it can be replaced without changing stored maps.
struct TerrainView: UIViewRepresentable {
    let package: MapPackage
    let photo: UIImage?
    let annotations: [MapAnnotation]
    let coverage: [RegionManifest]

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(Theme.background)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.scene = makeScene()
        context.coordinator.ids = annotations
        context.coordinator.coverage = coverage
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if context.coordinator.ids != annotations || context.coordinator.coverage != coverage {
            let camera = view.pointOfView?.transform
            view.scene = makeScene()
            if let camera { view.pointOfView?.transform = camera }
            context.coordinator.ids = annotations
            context.coordinator.coverage = coverage
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var ids: [MapAnnotation] = []
        var coverage: [RegionManifest] = []
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let bounds = package.bounds
        let width = bounds.bottomRight.x - bounds.topLeft.x
        let depth = (bounds.bottomRight.y - bounds.topLeft.y) / width * 10
        let elevation = package.elevation
        let groundWidth = width * 40_075_016.686 * cos(bounds.center.latitude * .pi / 180)
        // Explicitly labelled 12× exaggeration makes country-scale relief readable.
        let verticalScale = 10 / groundWidth * 12
        var vertices: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var indices: [Int32] = []
        for row in 0..<elevation.rows {
            for col in 0..<elevation.columns {
                let u = Double(col) / Double(elevation.columns - 1)
                let v = Double(row) / Double(elevation.rows - 1)
                let height = max(0, elevation.meters[row * elevation.columns + col]) * verticalScale
                vertices.append(SCNVector3((u - 0.5) * 10, height, (v - 0.5) * depth))
                texcoords.append(CGPoint(x: u, y: v))
                if row < elevation.rows - 1 && col < elevation.columns - 1 {
                    let i = Int32(row * elevation.columns + col)
                    let w = Int32(elevation.columns)
                    indices += [i, i + w, i + 1, i + 1, i + w, i + w + 1]
                }
            }
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(textureCoordinates: texcoords)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let material = SCNMaterial()
        material.diffuse.contents = photo ?? UIImage()
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))

        func position(_ coordinate: Coordinate) -> SCNVector3 {
            let point = coordinate.worldPoint
            let u = (point.x - bounds.topLeft.x) / width
            let v = (point.y - bounds.topLeft.y) / (bounds.bottomRight.y - bounds.topLeft.y)
            let col = min(elevation.columns - 1, max(0, Int(u * Double(elevation.columns - 1))))
            let row = min(elevation.rows - 1, max(0, Int(v * Double(elevation.rows - 1))))
            let height = max(0, elevation.meters[row * elevation.columns + col]) * verticalScale
            return SCNVector3((u - 0.5) * 10, height + 0.04, (v - 0.5) * depth)
        }
        for annotation in annotations {
            guard annotation.coordinates.allSatisfy(bounds.contains) else { continue }
            let color = UIColor(annotation.layer.color)
            if annotation.kind == .point, let coordinate = annotation.coordinates.first {
                let marker = SCNSphere(radius: 0.06)
                marker.firstMaterial?.diffuse.contents = color
                marker.firstMaterial?.lightingModel = .constant
                let node = SCNNode(geometry: marker)
                node.position = position(coordinate)
                scene.rootNode.addChildNode(node)
            } else {
                var points = annotation.coordinates.map(position)
                if annotation.kind == .area, let first = points.first { points.append(first) }
                let pairs = (0..<max(0, points.count - 1)).flatMap { [Int32($0), Int32($0 + 1)] }
                let line = SCNGeometry(
                    sources: [SCNGeometrySource(vertices: points)],
                    elements: [SCNGeometryElement(indices: pairs, primitiveType: .line)])
                line.firstMaterial?.diffuse.contents = color
                line.firstMaterial?.lightingModel = .constant
                scene.rootNode.addChildNode(SCNNode(geometry: line))
            }
        }
        for (index, region) in coverage.enumerated() {
            let b = region.bounds
            let coordinates = [
                Coordinate(latitude: b.south, longitude: b.west),
                Coordinate(latitude: b.south, longitude: b.east),
                Coordinate(latitude: b.north, longitude: b.east),
                Coordinate(latitude: b.north, longitude: b.west),
                Coordinate(latitude: b.south, longitude: b.west),
            ]
            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: coordinates.map(position))],
                elements: [SCNGeometryElement(indices: [Int32(0), 1, 1, 2, 2, 3, 3, 4], primitiveType: .line)])
            let material = SCNMaterial()
            material.diffuse.contents =
                index == 0
                ? UIColor(red: 0.96, green: 0.74, blue: 0.41, alpha: 1)
                : UIColor(red: 0.75, green: 0.64, blue: 0.90, alpha: 1)
            material.lightingModel = .constant
            geometry.materials = [material]
            scene.rootNode.addChildNode(SCNNode(geometry: geometry))
        }
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zFar = 200
        camera.position = SCNVector3(0, depth * 0.95, depth * 0.7)
        camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)
        return scene
    }
}
