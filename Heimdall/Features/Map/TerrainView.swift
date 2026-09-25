import SceneKit
import SwiftUI

/// The map revision recreates this view when the underlying package changes.
/// Overlay changes leave the terrain buffers, texture and camera intact.
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
        view.rendersContinuously = false
        let terrain = TerrainScene(package: package, photo: photo)
        terrain.update(annotations: annotations, coverage: coverage)
        context.coordinator.terrain = terrain
        view.scene = terrain.scene
        view.pointOfView = terrain.camera
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.terrain?.update(annotations: annotations, coverage: coverage)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var terrain: TerrainScene?
    }
}

@MainActor final class TerrainScene {
    let scene = SCNScene()
    let ground = SCNNode()
    let camera = SCNNode()
    let annotationNode = SCNNode()
    let coverageNode = SCNNode()
    private let bounds: MapBounds
    private let elevation: MapPackage.Elevation
    private let width: Double
    private let depth: Double
    private let verticalScale: Double
    private var annotations: [MapAnnotation] = []
    private var coverage: [RegionManifest] = []

    init(package: MapPackage, photo: UIImage?) {
        bounds = package.bounds
        elevation = package.elevation
        width = bounds.bottomRight.x - bounds.topLeft.x
        depth = (bounds.bottomRight.y - bounds.topLeft.y) / width * 10
        let groundWidth = width * 40_075_016.686 * cos(bounds.center.latitude * .pi / 180)
        // Country-scale relief remains exaggerated 12×.
        verticalScale = 10 / groundWidth * 12
        buildGround(photo: photo)
        camera.camera = SCNCamera()
        camera.camera?.zFar = 200
        camera.position = SCNVector3(0, depth * 0.95, depth * 0.7)
        camera.look(at: SCNVector3Zero)
        for node in [ground, annotationNode, coverageNode, camera] { scene.rootNode.addChildNode(node) }
    }

    func update(annotations: [MapAnnotation], coverage: [RegionManifest]) {
        if self.annotations != annotations {
            for node in annotationNode.childNodes { node.removeFromParentNode() }
            addAnnotations(annotations)
            self.annotations = annotations
        }
        if self.coverage != coverage {
            for node in coverageNode.childNodes { node.removeFromParentNode() }
            addCoverage(coverage)
            self.coverage = coverage
        }
    }

    private func buildGround(photo: UIImage?) {
        var vertices: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var indices: [Int32] = []
        vertices.reserveCapacity(elevation.rows * elevation.columns)
        texcoords.reserveCapacity(elevation.rows * elevation.columns)
        indices.reserveCapacity((elevation.rows - 1) * (elevation.columns - 1) * 6)
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
        ground.geometry = geometry
    }

    private func position(_ coordinate: Coordinate) -> SCNVector3 {
        let point = coordinate.worldPoint
        let u = (point.x - bounds.topLeft.x) / width
        let v = (point.y - bounds.topLeft.y) / (bounds.bottomRight.y - bounds.topLeft.y)
        let col = min(elevation.columns - 1, max(0, Int(u * Double(elevation.columns - 1))))
        let row = min(elevation.rows - 1, max(0, Int(v * Double(elevation.rows - 1))))
        let height = max(0, elevation.meters[row * elevation.columns + col]) * verticalScale
        return SCNVector3((u - 0.5) * 10, height + 0.04, (v - 0.5) * depth)
    }

    private func addAnnotations(_ annotations: [MapAnnotation]) {
        for annotation in annotations {
            guard annotation.coordinates.allSatisfy(bounds.contains) else { continue }
            let color = UIColor(annotation.layer.color)
            if annotation.kind == .point, let coordinate = annotation.coordinates.first {
                let marker = SCNSphere(radius: 0.06)
                marker.firstMaterial?.diffuse.contents = color
                marker.firstMaterial?.lightingModel = .constant
                let node = SCNNode(geometry: marker)
                node.position = position(coordinate)
                annotationNode.addChildNode(node)
            } else {
                var points = annotation.coordinates.map(position)
                if annotation.kind == .area, let first = points.first { points.append(first) }
                let pairs = (0..<max(0, points.count - 1)).flatMap { [Int32($0), Int32($0 + 1)] }
                let line = SCNGeometry(
                    sources: [SCNGeometrySource(vertices: points)],
                    elements: [SCNGeometryElement(indices: pairs, primitiveType: .line)])
                line.firstMaterial?.diffuse.contents = color
                line.firstMaterial?.lightingModel = .constant
                annotationNode.addChildNode(SCNNode(geometry: line))
            }
        }
    }

    private func addCoverage(_ coverage: [RegionManifest]) {
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
            coverageNode.addChildNode(SCNNode(geometry: geometry))
        }
    }
}
