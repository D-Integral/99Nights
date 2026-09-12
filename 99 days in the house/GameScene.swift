//
//  GameScene.swift
//  99 days in the house
//
//  Created by Dmytro Skorokhod on 29.06.2026.
//
//  3D survival game (SceneKit). Survive 99 days and save 4 kids.
//
//  THE PERSON has 100 lives. Enemies now hunt YOU (not the house):
//    🐺 wolf  -10 · 🐺(red eyes) angry wolf -40 · 👿 demon -15 · 👹 Red God -60
//  Run with the joystick to dodge, tap enemies to fight back.
//
//  DAY: hunt 🐰 bunnies (food + 🐾 bunny foot), chop 🌲 trees (🪵), mine 🪨 rocks
//       (🔩 metal), rescue 🧒 kids, open 💰 treasures, craft, and meet the trader.
//  NIGHT: the Red God + wolves come; raid nights add demons. The campfire burns
//       nearby enemies. With no 🍖 food you starve and lose lives.
//
//  Build everything from SceneKit primitives — no 3D model assets needed.
//

import SceneKit
import SpriteKit
import UIKit

enum GamePhase {
    case title
    case day
    case night
    case gameOver
    case win
}

struct DifficultyConfig {
    let name: String
    let blurb: String
    let startFood: Int
    let startWood: Int
    let startMetal: Int
    let attackPower: Int
    let redGodHP: Int
    let demonHP: Int
    let enemySpeedMultiplier: Float
    let damageTaken: Float
    let campfireDamage: Int
    let dayDuration: TimeInterval
    let nightDuration: TimeInterval
    let animalSpawn: ClosedRange<Double>
    let demonSpawn: ClosedRange<Double>
    let redGodRespawnDelay: TimeInterval
}

enum Difficulty: Int, CaseIterable {
    case easy, medium, difficult, insane, king

    var config: DifficultyConfig {
        switch self {
        case .easy:
            return DifficultyConfig(name: "Easy", blurb: "relaxed",
                startFood: 6, startWood: 10, startMetal: 3, attackPower: 2,
                redGodHP: 4, demonHP: 1, enemySpeedMultiplier: 0.7, damageTaken: 0.5,
                campfireDamage: 2, dayDuration: 130, nightDuration: 70,
                animalSpawn: 0.9...1.8, demonSpawn: 4.5...7.0, redGodRespawnDelay: 3.0)
        case .medium:
            return DifficultyConfig(name: "Medium", blurb: "a fair fight",
                startFood: 3, startWood: 4, startMetal: 0, attackPower: 1,
                redGodHP: 6, demonHP: 2, enemySpeedMultiplier: 1.0, damageTaken: 1.0,
                campfireDamage: 1, dayDuration: 120, nightDuration: 90,
                animalSpawn: 1.2...2.4, demonSpawn: 3.0...5.0, redGodRespawnDelay: 1.8)
        case .difficult:
            return DifficultyConfig(name: "Difficult", blurb: "tough enemies",
                startFood: 2, startWood: 2, startMetal: 0, attackPower: 1,
                redGodHP: 8, demonHP: 3, enemySpeedMultiplier: 1.2, damageTaken: 1.2,
                campfireDamage: 1, dayDuration: 110, nightDuration: 95,
                animalSpawn: 1.6...3.0, demonSpawn: 2.2...3.8, redGodRespawnDelay: 1.3)
        case .insane:
            return DifficultyConfig(name: "Insane", blurb: "brutal",
                startFood: 1, startWood: 0, startMetal: 0, attackPower: 1,
                redGodHP: 10, demonHP: 3, enemySpeedMultiplier: 1.4, damageTaken: 1.4,
                campfireDamage: 1, dayDuration: 100, nightDuration: 100,
                animalSpawn: 2.0...3.6, demonSpawn: 1.6...2.8, redGodRespawnDelay: 1.0)
        case .king:
            return DifficultyConfig(name: "King", blurb: "nearly impossible",
                startFood: 1, startWood: 0, startMetal: 0, attackPower: 1,
                redGodHP: 12, demonHP: 4, enemySpeedMultiplier: 1.6, damageTaken: 1.6,
                campfireDamage: 1, dayDuration: 95, nightDuration: 110,
                animalSpawn: 2.5...4.2, demonSpawn: 1.1...2.2, redGodRespawnDelay: 0.8)
        }
    }
}

final class GameWorld: NSObject {

    // A hostile that chases the player.
    private final class Enemy {
        let node: SCNNode
        var hp: Int
        let speed: Float
        let damage: Int
        let kind: String        // "wolf", "angryWolf", "demon", "redgod"
        init(node: SCNNode, hp: Int, speed: Float, damage: Int, kind: String) {
            self.node = node; self.hp = hp; self.speed = speed
            self.damage = damage; self.kind = kind
        }
    }

    // MARK: - Tunables
    private let maxDays = 99
    private let maxLives = 100
    private let wolfDamage = 10
    private let angryWolfDamage = 40
    private let demonDamage = 15
    private let redGodDamage = 60
    private let wolfHP = 2
    private let angryWolfHP = 4
    private let attackRange: Float = 1.9

    private var config = Difficulty.medium.config

    private let raidNights: Set<Int> = [3, 11, 24, 46, 50, 55, 61, 77, 89, 99]
    private let merchantDays: Set<Int> = [2, 4, 6, 18, 28, 38, 48, 58, 68, 78, 88, 98]

    private let frontZ: Float = 8.5
    private let spawnZ: Float = -18
    private let minX: Float = -13, maxX: Float = 13
    private let minZ: Float = -15, maxZ: Float = 10
    private let interactRange: Float = 4.0
    private let playerSpeed: Float = 8.5

    // MARK: - Public scene objects
    let scene = SCNScene()
    let hud: SKScene

    // MARK: - State
    private(set) var phase: GamePhase = .title
    private var day = 1
    private var lives = 100
    private var food = 3
    private var wood = 0
    private var metal = 0
    private var bunnyFeet = 0
    private var kidsSaved = 0
    private var attackPower = 1
    private var campfireLevel = 1
    private let maxCampfireLevel = 6

    // Tools / upgrades
    private var hasAxe = false
    private var hasBag = false
    private var hasKatana = false
    private var hasBed = false
    private var hasMap = false
    private var hasWolfCover = false
    private var bedUsedToday = false

    private var phaseTimeRemaining: TimeInterval = 0
    private var lastTick = Date()
    private var timer: Timer?
    private var campfireAoeAccumulator: TimeInterval = 0
    private var hungerAccumulator: TimeInterval = 0
    // Spawn/respawn/regrow scheduling driven from the main-thread game loop.
    // (Never schedule game-state changes via SCNAction callbacks — those run on
    // SceneKit's animation thread and would violate main-actor isolation.)
    private var daySpawnTimer: TimeInterval = 0
    private var nightSpawnTimer: TimeInterval = 0
    private var redGodRespawnTimer: TimeInterval?
    private var regrowTimers: [SCNNode: TimeInterval] = [:]

    // MARK: - 3D nodes
    private let cameraNode = SCNNode()
    private let sunLight = SCNLight()
    private let ambientLight = SCNLight()
    private var groundMaterial: SCNMaterial?
    private var groundNode: SCNNode?
    private var houseNode: SCNNode?
    private let playerNode = SCNNode()
    private var campfireNode: SCNNode?
    private var flameNode: SCNNode?
    private var campLight: SCNLight?
    private var craftTableNode: SCNNode?
    private var merchantNode: SCNNode?
    private var bedNode: SCNNode?

    private var enemies: [Enemy] = []
    private var treeChops: [SCNNode: Int] = [:]
    private var rockMetal: [SCNNode: Int] = [:]
    private var kidNodes: [SCNNode] = []
    private var treasureNodes: [SCNNode] = []

    // MARK: - Input state
    private var moveVec = CGVector(dx: 0, dy: 0)
    private let joystickCenter = CGPoint(x: 95, y: 95)
    private let joystickRadius: CGFloat = 60
    private let joystickActivation: CGFloat = 100
    private var craftingMenuOpen = false

    // MARK: - HUD nodes
    private let hudDay = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hudVit = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hudRes = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hudGear = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hudPhase = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hudTimer = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let overlay = SKNode()
    private let overlayTitle = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let overlaySub = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let authorLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private var damageFlash: SKShapeNode?
    private let joystickBase = SKShapeNode(circleOfRadius: 60)
    private let joystickKnob = SKShapeNode(circleOfRadius: 28)
    private let craftMenu = SKNode()
    private let difficultyButtons = SKNode()
    private var craftLabels: [String: SKLabelNode] = [:]
    private let campBarBG = SKShapeNode(rectOf: CGSize(width: 150, height: 12), cornerRadius: 6)
    private let campBarFill = SKShapeNode()
    private let campBarLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var viewSize: CGSize

    // MARK: - Init
    init(viewSize: CGSize) {
        self.viewSize = viewSize
        self.hud = SKScene(size: viewSize)
        super.init()
        buildWorld()
        buildHUD()
        showTitle()
        startTimer()
    }

    deinit { timer?.invalidate() }

    // MARK: - World construction
    private func buildWorld() {
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 62
        cameraNode.camera?.zFar = 200
        cameraNode.position = SCNVector3(0, 20, 33)
        let focus = SCNNode()
        focus.position = SCNVector3(0, 1, -1)
        scene.rootNode.addChildNode(focus)
        let look = SCNLookAtConstraint(target: focus)
        look.isGimbalLockEnabled = true
        cameraNode.constraints = [look]
        scene.rootNode.addChildNode(cameraNode)

        sunLight.type = .directional
        sunLight.intensity = 1000
        let sunNode = SCNNode()
        sunNode.light = sunLight
        sunNode.position = SCNVector3(10, 20, 10)
        sunNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(sunNode)

        ambientLight.type = .ambient
        ambientLight.intensity = 600
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        let ground = SCNPlane(width: 90, height: 90)
        let gMat = SCNMaterial()
        gMat.diffuse.contents = UIColor(red: 0.30, green: 0.55, blue: 0.25, alpha: 1)
        ground.materials = [gMat]
        groundMaterial = gMat
        let gNode = SCNNode(geometry: ground)
        gNode.eulerAngles.x = -Float.pi / 2
        scene.rootNode.addChildNode(gNode)
        groundNode = gNode

        scene.background.contents = UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1)

        buildHouse()
        buildCampfire()
        buildCraftTable()
        buildTrees()
        buildRocks()
        buildKids()
        buildTreasures()
        buildMerchant()
        buildPlayer()
    }

    private func buildHouse() {
        let house = SCNNode()
        let body = SCNBox(width: 6, height: 4, length: 5, chamferRadius: 0.2)
        body.firstMaterial?.diffuse.contents = UIColor(red: 0.62, green: 0.45, blue: 0.32, alpha: 1)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 2, 0)
        house.addChildNode(bodyNode)
        let roof = SCNPyramid(width: 7, height: 3, length: 6)
        roof.firstMaterial?.diffuse.contents = UIColor(red: 0.45, green: 0.18, blue: 0.15, alpha: 1)
        let roofNode = SCNNode(geometry: roof)
        roofNode.position = SCNVector3(0, 4, 0)
        house.addChildNode(roofNode)
        let door = SCNBox(width: 1.4, height: 2.2, length: 0.2, chamferRadius: 0)
        door.firstMaterial?.diffuse.contents = UIColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 1)
        let doorNode = SCNNode(geometry: door)
        doorNode.position = SCNVector3(0, 1.1, -2.55)
        house.addChildNode(doorNode)
        house.position = SCNVector3(0, 0, 12)
        scene.rootNode.addChildNode(house)
        houseNode = house
    }

    // The fire's glow expands the world: the map (ground) and the house grow
    // as the campfire evolves.
    private func applyWorldScale() {
        let f = 1.0 + Float(campfireLevel - 1) * 0.13
        groundNode?.scale = SCNVector3(f, f, 1)
        houseNode?.scale = SCNVector3(f, f, f)
    }

    private func buildCampfire() {
        let fire = SCNNode()
        fire.name = "campfire"
        for i in 0..<8 {
            let angle = Float(i) / 8 * 2 * .pi
            let stone = SCNSphere(radius: 0.22)
            stone.firstMaterial?.diffuse.contents = UIColor(white: 0.5, alpha: 1)
            let s = SCNNode(geometry: stone)
            s.position = SCNVector3(cos(angle) * 0.9, 0.1, sin(angle) * 0.9)
            fire.addChildNode(s)
        }
        for (dx, rot) in [(Float(-0.2), Float(0.4)), (0.25, -0.5)] {
            let log = SCNBox(width: 1.2, height: 0.18, length: 0.18, chamferRadius: 0.05)
            log.firstMaterial?.diffuse.contents = UIColor(red: 0.4, green: 0.26, blue: 0.14, alpha: 1)
            let l = SCNNode(geometry: log)
            l.position = SCNVector3(dx, 0.18, 0)
            l.eulerAngles.y = rot
            fire.addChildNode(l)
        }
        let flameGeo = SCNCone(topRadius: 0, bottomRadius: 0.55, height: 1.3)
        let fMat = SCNMaterial()
        fMat.diffuse.contents = UIColor.orange
        fMat.emission.contents = UIColor.orange
        flameGeo.materials = [fMat]
        let flame = SCNNode(geometry: flameGeo)
        flame.position = SCNVector3(0, 0.7, 0)
        flame.runAction(.repeatForever(.sequence([
            .scale(to: 1.15, duration: 0.25), .scale(to: 0.9, duration: 0.25)])))
        fire.addChildNode(flame)
        flameNode = flame
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor.orange
        light.intensity = 300
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = SCNVector3(0, 2, 0)
        fire.addChildNode(lightNode)
        campLight = light
        fire.position = SCNVector3(4.5, 0, 6)
        scene.rootNode.addChildNode(fire)
        campfireNode = fire
        updateCampfireVisual()
    }

    private func buildCraftTable() {
        let table = SCNNode()
        table.name = "crafttable"
        let top = SCNBox(width: 2.0, height: 0.25, length: 1.3, chamferRadius: 0.05)
        top.firstMaterial?.diffuse.contents = UIColor(red: 0.5, green: 0.35, blue: 0.2, alpha: 1)
        let topNode = SCNNode(geometry: top)
        topNode.position = SCNVector3(0, 1.0, 0)
        table.addChildNode(topNode)
        for (dx, dz) in [(Float(-0.8), Float(0.5)), (0.8, 0.5), (-0.8, -0.5), (0.8, -0.5)] {
            let leg = SCNBox(width: 0.18, height: 1.0, length: 0.18, chamferRadius: 0)
            leg.firstMaterial?.diffuse.contents = UIColor(red: 0.4, green: 0.27, blue: 0.15, alpha: 1)
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(dx, 0.5, dz)
            table.addChildNode(legNode)
        }
        let tool = SCNBox(width: 0.5, height: 0.4, length: 0.4, chamferRadius: 0.05)
        tool.firstMaterial?.diffuse.contents = UIColor(white: 0.35, alpha: 1)
        let toolNode = SCNNode(geometry: tool)
        toolNode.position = SCNVector3(0.4, 1.35, 0)
        table.addChildNode(toolNode)
        table.position = SCNVector3(-4.5, 0, 6)
        scene.rootNode.addChildNode(table)
        craftTableNode = table
    }

    private func buildTrees() {
        let positions: [(Float, Float)] = [
            (-11, -2), (-8, -9), (-3, -12), (3, -11), (9, -8),
            (12, -1), (10, 4), (-12, 5), (-6, 1), (6, 2)
        ]
        for (x, z) in positions {
            let tree = makeTree()
            tree.position = SCNVector3(x, 0, z)
            scene.rootNode.addChildNode(tree)
            treeChops[tree] = 4
        }
    }

    private func makeTree() -> SCNNode {
        let tree = SCNNode()
        tree.name = "tree"
        let trunk = SCNCylinder(radius: 0.35, height: 2.2)
        trunk.firstMaterial?.diffuse.contents = UIColor(red: 0.42, green: 0.28, blue: 0.16, alpha: 1)
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position = SCNVector3(0, 1.1, 0)
        tree.addChildNode(trunkNode)
        for (y, r) in [(Float(2.4), Float(1.4)), (3.3, 1.1), (4.0, 0.75)] {
            let leaves = SCNCone(topRadius: 0, bottomRadius: CGFloat(r), height: 1.4)
            leaves.firstMaterial?.diffuse.contents = UIColor(red: 0.16, green: 0.45, blue: 0.20, alpha: 1)
            let lNode = SCNNode(geometry: leaves)
            lNode.position = SCNVector3(0, y, 0)
            tree.addChildNode(lNode)
        }
        return tree
    }

    private func buildRocks() {
        let positions: [(Float, Float)] = [(-10, 3), (8, -4), (-1, -14), (11, 2)]
        for (x, z) in positions {
            let rock = makeRock()
            rock.position = SCNVector3(x, 0, z)
            scene.rootNode.addChildNode(rock)
            rockMetal[rock] = 4
        }
    }

    private func makeRock() -> SCNNode {
        let rock = SCNNode()
        rock.name = "rock"
        for (dx, dy, dz, r) in [(Float(0), Float(0.4), Float(0), Float(0.9)),
                                (0.6, 0.25, 0.2, 0.55),
                                (-0.5, 0.2, -0.3, 0.5)] {
            let g = SCNSphere(radius: CGFloat(r))
            g.firstMaterial?.diffuse.contents = UIColor(white: 0.45, alpha: 1)
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(dx, dy, dz)
            rock.addChildNode(n)
        }
        // metallic glints
        for _ in 0..<3 {
            let g = SCNSphere(radius: 0.12)
            g.firstMaterial?.diffuse.contents = UIColor(red: 0.8, green: 0.7, blue: 0.4, alpha: 1)
            g.firstMaterial?.metalness.contents = 1.0
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(Float.random(in: -0.5...0.5), Float.random(in: 0.3...0.7), Float.random(in: -0.4...0.5))
            rock.addChildNode(n)
        }
        return rock
    }

    private func buildKids() {
        let positions: [(Float, Float)] = [(-12, -13), (12, -13), (-12, 9), (12, 9)]
        let colors = [UIColor.systemYellow, UIColor.systemTeal, UIColor.systemPink, UIColor.systemGreen]
        for (i, (x, z)) in positions.enumerated() {
            let kid = makeKid(color: colors[i])
            kid.position = SCNVector3(x, 0, z)
            scene.rootNode.addChildNode(kid)
            kidNodes.append(kid)
        }
    }

    private func makeKid(color: UIColor) -> SCNNode {
        let kid = SCNNode()
        kid.name = "kid"
        let body = SCNBox(width: 0.45, height: 0.6, length: 0.3, chamferRadius: 0.08)
        body.firstMaterial?.diffuse.contents = color
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.75, 0)
        kid.addChildNode(bodyNode)
        let head = SCNSphere(radius: 0.24)
        head.firstMaterial?.diffuse.contents = UIColor(red: 0.95, green: 0.78, blue: 0.6, alpha: 1)
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.3, 0)
        kid.addChildNode(headNode)
        // simple cage bars
        for dx in [Float(-0.6), 0.6] {
            for dz in [Float(-0.6), 0.6] {
                let bar = SCNCylinder(radius: 0.05, height: 2.0)
                bar.firstMaterial?.diffuse.contents = UIColor(white: 0.3, alpha: 1)
                let barNode = SCNNode(geometry: bar)
                barNode.position = SCNVector3(dx, 1.0, dz)
                kid.addChildNode(barNode)
            }
        }
        kid.runAction(.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.12, z: 0, duration: 0.5),
            .moveBy(x: 0, y: -0.12, z: 0, duration: 0.5)])))
        return kid
    }

    private func buildTreasures() {
        let positions: [(Float, Float)] = [(-6, -8), (5, -9), (-9, -1)]
        for (x, z) in positions {
            let chest = makeTreasure()
            chest.position = SCNVector3(x, 0, z)
            scene.rootNode.addChildNode(chest)
            treasureNodes.append(chest)
        }
    }

    private func makeTreasure() -> SCNNode {
        let chest = SCNNode()
        chest.name = "treasure"
        let box = SCNBox(width: 0.9, height: 0.6, length: 0.6, chamferRadius: 0.06)
        box.firstMaterial?.diffuse.contents = UIColor(red: 0.5, green: 0.32, blue: 0.14, alpha: 1)
        let boxNode = SCNNode(geometry: box)
        boxNode.position = SCNVector3(0, 0.35, 0)
        chest.addChildNode(boxNode)
        let lid = SCNBox(width: 0.95, height: 0.2, length: 0.65, chamferRadius: 0.06)
        let lidMat = SCNMaterial()
        lidMat.diffuse.contents = UIColor(red: 0.85, green: 0.7, blue: 0.2, alpha: 1)
        lidMat.metalness.contents = 0.8
        lid.materials = [lidMat]
        let lidNode = SCNNode(geometry: lid)
        lidNode.position = SCNVector3(0, 0.72, 0)
        chest.addChildNode(lidNode)
        return chest
    }

    private func buildMerchant() {
        let m = SCNNode()
        m.name = "merchant"
        let robe = SCNCone(topRadius: 0.25, bottomRadius: 0.7, height: 1.6)
        robe.firstMaterial?.diffuse.contents = UIColor(red: 0.35, green: 0.2, blue: 0.5, alpha: 1)
        let robeNode = SCNNode(geometry: robe)
        robeNode.position = SCNVector3(0, 0.8, 0)
        m.addChildNode(robeNode)
        let head = SCNSphere(radius: 0.3)
        head.firstMaterial?.diffuse.contents = UIColor(red: 0.95, green: 0.78, blue: 0.6, alpha: 1)
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.7, 0)
        m.addChildNode(headNode)
        let hat = SCNCone(topRadius: 0, bottomRadius: 0.45, height: 0.6)
        hat.firstMaterial?.diffuse.contents = UIColor(red: 0.2, green: 0.12, blue: 0.3, alpha: 1)
        let hatNode = SCNNode(geometry: hat)
        hatNode.position = SCNVector3(0, 2.1, 0)
        m.addChildNode(hatNode)
        // a glowing "?" marker beacon
        let beacon = SCNSphere(radius: 0.18)
        let bMat = SCNMaterial()
        bMat.diffuse.contents = UIColor.yellow
        bMat.emission.contents = UIColor.yellow
        beacon.materials = [bMat]
        let beaconNode = SCNNode(geometry: beacon)
        beaconNode.position = SCNVector3(0, 2.8, 0)
        beaconNode.runAction(.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.2, z: 0, duration: 0.6),
            .moveBy(x: 0, y: -0.2, z: 0, duration: 0.6)])))
        m.addChildNode(beaconNode)
        m.position = SCNVector3(3, 0, 9)
        m.isHidden = true
        scene.rootNode.addChildNode(m)
        merchantNode = m
    }

    private func buildPlayer() {
        let skin = UIColor(red: 0.95, green: 0.78, blue: 0.6, alpha: 1)
        let shirt = UIColor(red: 0.15, green: 0.5, blue: 0.75, alpha: 1)
        let pants = UIColor(red: 0.2, green: 0.22, blue: 0.28, alpha: 1)
        let body = SCNBox(width: 0.7, height: 0.9, length: 0.4, chamferRadius: 0.1)
        body.firstMaterial?.diffuse.contents = shirt
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 1.15, 0)
        playerNode.addChildNode(bodyNode)
        let head = SCNSphere(radius: 0.32)
        head.firstMaterial?.diffuse.contents = skin
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.95, 0)
        playerNode.addChildNode(headNode)
        for dx in [Float(-0.18), 0.18] {
            let leg = SCNBox(width: 0.22, height: 0.8, length: 0.25, chamferRadius: 0.05)
            leg.firstMaterial?.diffuse.contents = pants
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(dx, 0.4, 0)
            playerNode.addChildNode(legNode)
        }
        for dx in [Float(-0.5), 0.5] {
            let arm = SCNBox(width: 0.18, height: 0.75, length: 0.22, chamferRadius: 0.05)
            arm.firstMaterial?.diffuse.contents = shirt
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(dx, 1.15, 0)
            playerNode.addChildNode(armNode)
        }
        for dx in [Float(-0.12), 0.12] {
            let eye = SCNSphere(radius: 0.05)
            eye.firstMaterial?.diffuse.contents = UIColor.black
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(dx, 1.98, -0.28)
            playerNode.addChildNode(eyeNode)
        }
        playerNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(playerNode)
    }

    // MARK: - Enemy builders
    private func makeRedGod() -> SCNNode {
        let group = SCNNode()
        group.name = "redgod"
        let red = UIColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1)
        let bMat = SCNMaterial()
        bMat.diffuse.contents = red
        bMat.emission.contents = UIColor(red: 0.4, green: 0, blue: 0, alpha: 1)
        let body = SCNBox(width: 1.8, height: 2.6, length: 1.2, chamferRadius: 0.2)
        body.materials = [bMat]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 1.8, 0)
        group.addChildNode(bodyNode)
        let head = SCNSphere(radius: 0.9)
        let hMat = SCNMaterial()
        hMat.diffuse.contents = red
        hMat.emission.contents = UIColor(red: 0.5, green: 0, blue: 0, alpha: 1)
        head.materials = [hMat]
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 3.6, 0)
        group.addChildNode(headNode)
        // FOUR white eyes
        for (dx, dy) in [(Float(-0.45), Float(3.95)), (0.45, 3.95), (-0.25, 3.45), (0.25, 3.45)] {
            let eye = SCNSphere(radius: 0.16)
            let eMat = SCNMaterial()
            eMat.diffuse.contents = UIColor.white
            eMat.emission.contents = UIColor.white
            eye.materials = [eMat]
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(dx, dy, 0.78)
            group.addChildNode(eyeNode)
        }
        for dx in [Float(-0.55), 0.55] {
            let horn = SCNPyramid(width: 0.3, height: 0.8, length: 0.3)
            let hornMat = SCNMaterial()
            hornMat.diffuse.contents = UIColor(red: 0.3, green: 0, blue: 0, alpha: 1)
            horn.materials = [hornMat]
            let hornNode = SCNNode(geometry: horn)
            hornNode.position = SCNVector3(dx, 4.4, 0)
            group.addChildNode(hornNode)
        }
        for dx in [Float(-1.2), 1.2] {
            let arm = SCNBox(width: 0.4, height: 1.8, length: 0.4, chamferRadius: 0.1)
            arm.materials = [bMat]
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(dx, 2.0, 0)
            group.addChildNode(armNode)
        }
        return group
    }

    private func makeDemon() -> SCNNode {
        let group = SCNNode()
        group.name = "demon"
        let maroon = UIColor(red: 0.55, green: 0.08, blue: 0.12, alpha: 1)
        let mat = SCNMaterial()
        mat.diffuse.contents = maroon
        mat.emission.contents = UIColor(red: 0.25, green: 0, blue: 0, alpha: 1)
        let body = SCNBox(width: 0.6, height: 0.9, length: 0.45, chamferRadius: 0.1)
        body.materials = [mat]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.85, 0)
        group.addChildNode(bodyNode)
        let head = SCNSphere(radius: 0.35)
        head.materials = [mat]
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.5, 0)
        group.addChildNode(headNode)
        for dx in [Float(-0.13), 0.13] {
            let eye = SCNSphere(radius: 0.07)
            let eMat = SCNMaterial()
            eMat.diffuse.contents = UIColor.orange
            eMat.emission.contents = UIColor.orange
            eye.materials = [eMat]
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(dx, 1.55, 0.3)
            group.addChildNode(eyeNode)
        }
        for dx in [Float(-0.18), 0.18] {
            let horn = SCNPyramid(width: 0.12, height: 0.3, length: 0.12)
            horn.materials = [mat]
            let hornNode = SCNNode(geometry: horn)
            hornNode.position = SCNVector3(dx, 1.8, 0)
            group.addChildNode(hornNode)
        }
        return group
    }

    private func makeWolf(angry: Bool) -> SCNNode {
        let group = SCNNode()
        group.name = angry ? "angryWolf" : "wolf"
        let coat = angry ? UIColor(red: 0.28, green: 0.18, blue: 0.20, alpha: 1)
                         : UIColor(red: 0.42, green: 0.43, blue: 0.47, alpha: 1)
        let body = SCNBox(width: 0.8, height: 0.7, length: 1.6, chamferRadius: 0.15)
        body.firstMaterial?.diffuse.contents = coat
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.7, 0)
        if angry { bodyNode.scale = SCNVector3(1.2, 1.2, 1.2) }
        group.addChildNode(bodyNode)
        let head = SCNBox(width: 0.55, height: 0.55, length: 0.6, chamferRadius: 0.1)
        head.firstMaterial?.diffuse.contents = coat
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 0.9, 0.95)
        group.addChildNode(headNode)
        let eyeColor: UIColor = angry ? .red : .yellow
        for dx in [Float(-0.18), 0.18] {
            let eye = SCNSphere(radius: angry ? 0.1 : 0.07)
            let eMat = SCNMaterial()
            eMat.diffuse.contents = eyeColor
            eMat.emission.contents = eyeColor
            eye.materials = [eMat]
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(dx, 1.0, 1.25)
            group.addChildNode(eyeNode)
        }
        for (dx, dz) in [(Float(-0.3), Float(0.5)), (0.3, 0.5), (-0.3, -0.5), (0.3, -0.5)] {
            let leg = SCNBox(width: 0.18, height: 0.5, length: 0.18, chamferRadius: 0)
            leg.firstMaterial?.diffuse.contents = coat
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(dx, 0.25, dz)
            group.addChildNode(legNode)
        }
        return group
    }

    private func makeBunny() -> SCNNode {
        let group = SCNNode()
        group.name = "bunny"
        let white = UIColor(white: 0.95, alpha: 1)
        let body = SCNSphere(radius: 0.55)
        body.firstMaterial?.diffuse.contents = white
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.55, 0)
        bodyNode.scale = SCNVector3(1, 0.9, 1.3)
        group.addChildNode(bodyNode)
        let head = SCNSphere(radius: 0.35)
        head.firstMaterial?.diffuse.contents = white
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 0.75, 0.6)
        group.addChildNode(headNode)
        for dx in [Float(-0.13), 0.13] {
            let ear = SCNCapsule(capRadius: 0.07, height: 0.55)
            ear.firstMaterial?.diffuse.contents = white
            let earNode = SCNNode(geometry: ear)
            earNode.position = SCNVector3(dx, 1.15, 0.55)
            group.addChildNode(earNode)
        }
        return group
    }

    // MARK: - HUD
    private func buildHUD() {
        hud.scaleMode = .resizeFill
        hud.anchorPoint = CGPoint(x: 0, y: 0)
        hud.backgroundColor = .clear
        hud.isUserInteractionEnabled = false
        let top = viewSize.height - 28
        configureLabel(hudDay, size: 19, align: .left, at: CGPoint(x: 14, y: top - 20))
        configureLabel(hudVit, size: 17, align: .left, at: CGPoint(x: 14, y: top - 42))
        configureLabel(hudRes, size: 15, align: .left, at: CGPoint(x: 14, y: top - 62))
        configureLabel(hudGear, size: 15, align: .left, at: CGPoint(x: 14, y: top - 82))
        configureLabel(hudPhase, size: 15, align: .right, at: CGPoint(x: viewSize.width - 14, y: top - 20))
        configureLabel(hudTimer, size: 17, align: .right, at: CGPoint(x: viewSize.width - 14, y: top - 42))

        let flash = SKShapeNode(rect: CGRect(origin: .zero, size: viewSize))
        flash.fillColor = .red
        flash.strokeColor = .clear
        flash.alpha = 0
        flash.zPosition = 90
        hud.addChild(flash)
        damageFlash = flash

        buildCampfireBar(topY: top)
        buildJoystick()
        buildCraftMenu()
        buildMenuOverlay()
        updateHUD()
        updateCampfireBar()
    }

    private func buildCampfireBar(topY: CGFloat) {
        let label = campBarLabel
        label.fontSize = 13
        label.fontColor = .white
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 14, y: topY - 104)
        label.zPosition = 100
        hud.addChild(label)

        let barX: CGFloat = 100
        campBarBG.fillColor = SKColor(white: 1, alpha: 0.15)
        campBarBG.strokeColor = SKColor(white: 1, alpha: 0.4)
        campBarBG.lineWidth = 1
        campBarBG.position = CGPoint(x: barX + 75, y: topY - 104)
        campBarBG.zPosition = 100
        hud.addChild(campBarBG)

        campBarFill.fillColor = SKColor.orange
        campBarFill.strokeColor = .clear
        campBarFill.position = CGPoint(x: barX, y: topY - 104)   // left edge anchor
        campBarFill.zPosition = 101
        hud.addChild(campBarFill)
    }

    private func updateCampfireBar() {
        let pct = Float(campfireLevel) / Float(maxCampfireLevel)
        campBarLabel.text = "🔥 \(Int((pct * 100).rounded()))%"
        let fullWidth: CGFloat = 150
        let w = max(2, fullWidth * CGFloat(pct))
        campBarFill.path = CGPath(roundedRect: CGRect(x: 0, y: -6, width: w, height: 12),
                                  cornerWidth: 6, cornerHeight: 6, transform: nil)
    }

    private func configureLabel(_ label: SKLabelNode, size: CGFloat,
                                align: SKLabelHorizontalAlignmentMode, at pos: CGPoint) {
        label.fontSize = size
        label.fontColor = .white
        label.horizontalAlignmentMode = align
        label.position = pos
        label.zPosition = 100
        hud.addChild(label)
    }

    private func buildJoystick() {
        joystickBase.fillColor = SKColor(white: 1, alpha: 0.12)
        joystickBase.strokeColor = SKColor(white: 1, alpha: 0.35)
        joystickBase.lineWidth = 2
        joystickBase.position = joystickCenter
        joystickBase.zPosition = 95
        hud.addChild(joystickBase)
        joystickKnob.fillColor = SKColor(white: 1, alpha: 0.4)
        joystickKnob.strokeColor = SKColor(white: 1, alpha: 0.7)
        joystickKnob.position = joystickCenter
        joystickKnob.zPosition = 96
        hud.addChild(joystickKnob)
        setJoystickVisible(false)
    }

    private func setJoystickVisible(_ visible: Bool) {
        let a: CGFloat = visible ? 1 : 0
        joystickBase.alpha = a
        joystickKnob.alpha = a
    }

    private func buildCraftMenu() {
        craftMenu.zPosition = 210
        craftMenu.isHidden = true
        let dim = SKShapeNode(rect: CGRect(origin: .zero, size: viewSize))
        dim.fillColor = SKColor(white: 0, alpha: 0.6)
        dim.strokeColor = .clear
        craftMenu.addChild(dim)
        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "CRAFTING TABLE"
        title.fontSize = 26
        title.fontColor = .white
        title.position = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.72)
        craftMenu.addChild(title)

        let recipes = ["craft_katana", "craft_axe", "craft_bag", "craft_bed", "craft_map"]
        let topY = viewSize.height * 0.60
        let step = viewSize.height * 0.085
        for (i, name) in recipes.enumerated() {
            let lbl = SKLabelNode(fontNamed: "AvenirNext-Medium")
            craftLabels[name] = lbl
            let btn = makeButton(name: name, at: CGPoint(x: viewSize.width / 2, y: topY - CGFloat(i) * step), label: lbl)
            craftMenu.addChild(btn)
        }
        let close = makeButton(name: "craft_close",
                               at: CGPoint(x: viewSize.width / 2, y: topY - CGFloat(recipes.count) * step), label: nil)
        if let lbl = close.childNode(withName: "label") as? SKLabelNode { lbl.text = "Close" }
        craftMenu.addChild(close)
        hud.addChild(craftMenu)
    }

    private func makeButton(name: String, at pos: CGPoint, label: SKLabelNode?) -> SKNode {
        let btn = SKShapeNode(rectOf: CGSize(width: viewSize.width * 0.78, height: 46), cornerRadius: 11)
        btn.name = name
        btn.fillColor = SKColor(red: 0.2, green: 0.22, blue: 0.3, alpha: 0.95)
        btn.strokeColor = SKColor(white: 1, alpha: 0.5)
        btn.position = pos
        let text = label ?? SKLabelNode(fontNamed: "AvenirNext-Medium")
        text.name = "label"
        text.fontSize = 17
        text.fontColor = .white
        text.verticalAlignmentMode = .center
        text.horizontalAlignmentMode = .center
        text.position = .zero
        btn.addChild(text)
        return btn
    }

    private func buildMenuOverlay() {
        overlay.zPosition = 200
        let dim = SKShapeNode(rect: CGRect(origin: .zero, size: viewSize))
        dim.fillColor = SKColor(white: 0, alpha: 0.65)
        dim.strokeColor = .clear
        overlay.addChild(dim)
        overlayTitle.fontSize = 30
        overlayTitle.fontColor = .white
        overlayTitle.horizontalAlignmentMode = .center
        overlayTitle.numberOfLines = 0
        overlayTitle.preferredMaxLayoutWidth = viewSize.width - 60
        overlayTitle.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 + 40)
        overlay.addChild(overlayTitle)
        overlaySub.fontSize = 17
        overlaySub.fontColor = SKColor(white: 0.85, alpha: 1)
        overlaySub.horizontalAlignmentMode = .center
        overlaySub.numberOfLines = 0
        overlaySub.preferredMaxLayoutWidth = viewSize.width - 60
        overlaySub.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 - 80)
        overlay.addChild(overlaySub)
        authorLabel.text = "Created by Dominick Skorokhod"
        authorLabel.fontSize = 14
        authorLabel.fontColor = SKColor(white: 0.75, alpha: 1)
        authorLabel.horizontalAlignmentMode = .center
        authorLabel.position = CGPoint(x: viewSize.width / 2, y: 24)
        overlay.addChild(authorLabel)

        buildDifficultyButtons()
        overlay.addChild(difficultyButtons)
        hud.addChild(overlay)
    }

    private func buildDifficultyButtons() {
        let cases = Difficulty.allCases
        let topY = viewSize.height * 0.58
        let step = viewSize.height * 0.092
        for (i, diff) in cases.enumerated() {
            let c = diff.config
            let btn = makeButton(name: "diff_\(diff.rawValue)",
                                 at: CGPoint(x: viewSize.width / 2, y: topY - CGFloat(i) * step), label: nil)
            if let lbl = btn.childNode(withName: "label") as? SKLabelNode {
                lbl.text = "\(c.name) — \(c.blurb)"
            }
            difficultyButtons.addChild(btn)
        }
    }

    private func updateHUD() {
        hudDay.text = "Day \(day)/\(maxDays)"
        hudVit.text = "❤️ \(max(0, lives))   🍖 \(food)"
        hudRes.text = "🪵\(wood)  🔩\(metal)  🐾\(bunnyFeet)"
        hudGear.text = "🗡\(attackPower)  🔥\(campfireLevel)  🧒\(kidsSaved)/4"
        switch phase {
        case .day:
            hudPhase.text = merchantDays.contains(day) ? "☀️ DAY · Trader here!" : "☀️ DAY"
            hudTimer.text = timeString(phaseTimeRemaining)
        case .night:
            hudPhase.text = isRaidNight(day) ? "🌙 RAID NIGHT" : "🌙 NIGHT"
            hudTimer.text = timeString(phaseTimeRemaining)
        default:
            hudPhase.text = ""
            hudTimer.text = ""
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "⏱ %d:%02d", s / 60, s % 60)
    }

    private func updateCraftLabels() {
        craftLabels["craft_katana"]?.text = hasKatana ? "🗡 Katana — Owned" : "🗡 Katana (6🪵 5🔩) +2 atk"
        craftLabels["craft_axe"]?.text = hasAxe ? "🪓 Axe — Owned" : "🪓 Axe (4🪵 3🔩) +1 wood/chop"
        craftLabels["craft_bag"]?.text = hasBag ? "🎒 Bag — Owned" : "🎒 Bag (5🪵 2🔩) +1 per gather"
        craftLabels["craft_bed"]?.text = hasBed ? "🛏 Bed — Owned (rest to heal)" : "🛏 Bed (10🪵 4🔩) rest to heal"
        craftLabels["craft_map"]?.text = hasMap ? "🗺 Map — Owned" : "🗺 Map (6🪵 2🔩) reveal kids/treasure"
    }

    // MARK: - Screens
    private func showTitle() {
        phase = .title
        overlay.isHidden = false
        difficultyButtons.isHidden = false
        authorLabel.isHidden = false
        setJoystickVisible(false)
        overlayTitle.fontSize = 26
        overlayTitle.position = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.88)
        overlayTitle.text = "99 DAYS IN THE HOUSE"
        overlaySub.position = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.74)
        overlaySub.text = "Survive 99 days · save 🧒×4 · enemies hunt YOU\nRun to dodge, tap to fight. Choose difficulty:"
        updateHUD()
    }

    private func startGame(_ difficulty: Difficulty) {
        config = difficulty.config
        day = 1
        lives = maxLives
        food = config.startFood
        wood = config.startWood
        metal = config.startMetal
        bunnyFeet = 0
        kidsSaved = 0
        attackPower = config.attackPower
        campfireLevel = 1
        hasAxe = false; hasBag = false; hasKatana = false
        hasBed = false; hasMap = false; hasWolfCover = false
        bedUsedToday = false
        updateCampfireVisual()

        clearEnemies()
        removeAllBunnies()
        regrowAllTrees()
        regrowAllRocks()
        resetKidsAndTreasures()
        bedNode?.removeFromParentNode(); bedNode = nil
        closeCraftMenu()
        playerNode.position = SCNVector3(0, 0, 4)

        overlay.isHidden = true
        difficultyButtons.isHidden = true
        setJoystickVisible(true)
        startDay()
    }

    // MARK: - Day phase
    private func startDay() {
        phase = .day
        phaseTimeRemaining = config.dayDuration
        bedUsedToday = false
        applyDayLighting()
        flashBanner("☀️ Day \(day)", color: .white)
        if merchantDays.contains(day) {
            merchantNode?.isHidden = false
            flashBanner("🧙 A trader has arrived!", color: .yellow)
        } else {
            merchantNode?.isHidden = true
        }
        updateHUD()
        resetDaySpawnTimer()
    }

    private func applyDayLighting() {
        sunLight.color = UIColor.white
        sunLight.intensity = 1000
        ambientLight.color = UIColor(white: 0.6, alpha: 1)
        ambientLight.intensity = 600
        scene.background.contents = UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1)
        groundMaterial?.diffuse.contents = UIColor(red: 0.30, green: 0.55, blue: 0.25, alpha: 1)
        updateCampfireVisual()
    }

    private func resetDaySpawnTimer() {
        daySpawnTimer = Double.random(in: config.animalSpawn)
    }

    private func spawnDayCreature() {
        guard phase == .day else { return }
        let roll = Int.random(in: 0..<100)
        let angryChance = min(20, 4 + day / 6)
        if roll < 55 {
            spawnBunny()
        } else if roll < 100 - angryChance {
            spawnHostileWolf(angry: false)
        } else {
            spawnHostileWolf(angry: true)
        }
    }

    private func spawnBunny() {
        let node = makeBunny()
        let x = Float.random(in: minX...maxX)
        node.position = SCNVector3(x, 0, spawnZ)
        scene.rootNode.addChildNode(node)
        let speed = Double.random(in: 4.0...6.0)
        let move = SCNAction.move(to: SCNVector3(x, 0, maxZ + 4), duration: speed)
        move.timingMode = .linear
        node.runAction(SCNAction.sequence([move, .removeFromParentNode()]))
    }

    private func killBunny(_ node: SCNNode) {
        node.removeAllActions()
        node.name = "dead"
        food += 1
        bunnyFeet += 1
        floatText("+1🍖 +1🐾", color: .green)
        node.runAction(SCNAction.sequence([
            SCNAction.group([SCNAction.scale(to: 1.6, duration: 0.12),
                             SCNAction.fadeOut(duration: 0.12)]),
            SCNAction.removeFromParentNode()]))
        updateHUD()
    }

    private func removeAllBunnies() {
        for n in scene.rootNode.childNodes where n.name == "bunny" || n.name == "dead" {
            n.removeFromParentNode()
        }
    }

    private func endDay() {
        removeAllBunnies()
        merchantNode?.isHidden = true
        startNight()
    }

    // MARK: - Night phase
    private func isRaidNight(_ d: Int) -> Bool { raidNights.contains(d) }

    private func startNight() {
        phase = .night
        phaseTimeRemaining = config.nightDuration
        campfireAoeAccumulator = 0
        applyNightLighting()
        if food > 0 {
            food -= 1
            flashBanner("🌙 Night \(day)", color: .white)
        } else {
            flashBanner("🌙 Night \(day) — no food!", color: .red)
        }
        updateHUD()
        guard phase == .night else { return }
        redGodRespawnTimer = nil
        spawnRedGod()
        resetNightSpawnTimer()
        if isRaidNight(day) {
            flashBanner("⚠️ RAID! Demons are coming!", color: .orange)
        }
    }

    private func applyNightLighting() {
        sunLight.color = UIColor(red: 0.7, green: 0.2, blue: 0.2, alpha: 1)
        sunLight.intensity = 300
        ambientLight.color = UIColor(red: 0.2, green: 0.1, blue: 0.2, alpha: 1)
        ambientLight.intensity = 180
        scene.background.contents = UIColor(red: 0.08, green: 0.02, blue: 0.06, alpha: 1)
        groundMaterial?.diffuse.contents = UIColor(red: 0.12, green: 0.10, blue: 0.10, alpha: 1)
        updateCampfireVisual()
    }

    private func resetNightSpawnTimer() {
        let interval = isRaidNight(day) ? config.demonSpawn : (config.demonSpawn.lowerBound + 1.0)...(config.demonSpawn.upperBound + 2.0)
        nightSpawnTimer = Double.random(in: interval)
    }

    private func spawnNightCreature() {
        guard phase == .night else { return }
        if isRaidNight(day) && Bool.random() {
            spawnDemon()
        } else {
            spawnHostileWolf(angry: Int.random(in: 0..<100) < min(45, 15 + day / 4))
        }
    }

    // MARK: - Enemies
    private func spawnHostileWolf(angry: Bool) {
        let node = makeWolf(angry: angry)
        let x = Float.random(in: minX...maxX)
        node.position = SCNVector3(x, 0, spawnZ)
        scene.rootNode.addChildNode(node)
        let speed = (angry ? 4.2 : 3.2) * config.enemySpeedMultiplier
        let e = Enemy(node: node, hp: angry ? angryWolfHP : wolfHP, speed: speed,
                      damage: angry ? angryWolfDamage : wolfDamage,
                      kind: angry ? "angryWolf" : "wolf")
        enemies.append(e)
    }

    private func spawnDemon() {
        let node = makeDemon()
        let x = Float.random(in: minX...maxX)
        node.position = SCNVector3(x, 0, spawnZ)
        scene.rootNode.addChildNode(node)
        let e = Enemy(node: node, hp: config.demonHP, speed: 3.6 * config.enemySpeedMultiplier,
                      damage: demonDamage, kind: "demon")
        enemies.append(e)
    }

    private func spawnRedGod() {
        guard phase == .night else { return }
        let node = makeRedGod()
        let x = Float.random(in: -8...8)
        node.position = SCNVector3(x, 0, spawnZ)
        scene.rootNode.addChildNode(node)
        node.runAction(.repeatForever(.sequence([
            .scale(to: 1.08, duration: 0.5), .scale(to: 1.0, duration: 0.5)])), forKey: "pulse")
        let e = Enemy(node: node, hp: config.redGodHP, speed: 2.4 * config.enemySpeedMultiplier,
                      damage: redGodDamage, kind: "redgod")
        enemies.append(e)
    }

    private func enemy(for node: SCNNode) -> Enemy? {
        enemies.first { $0.node === node }
    }

    private func hitEnemy(_ e: Enemy) {
        e.hp -= attackPower
        e.node.runAction(SCNAction.sequence([
            SCNAction.scale(to: 0.85, duration: 0.05),
            SCNAction.scale(to: 1.0, duration: 0.05)]))
        if e.hp <= 0 { defeatEnemy(e, byPlayer: true) }
    }

    private func defeatEnemy(_ e: Enemy, byPlayer: Bool) {
        guard let idx = enemies.firstIndex(where: { $0 === e }) else { return }
        enemies.remove(at: idx)
        e.node.removeAllActions()
        e.node.name = "dead"
        if e.kind == "redgod" {
            floatText("REPELLED!", color: .green)
            scheduleRedGodRespawn()
        } else if byPlayer {
            food += 1
            floatText("+1🍖", color: .green)
            updateHUD()
        }
        e.node.runAction(SCNAction.sequence([
            SCNAction.group([SCNAction.scale(to: 1.6, duration: 0.18),
                             SCNAction.fadeOut(duration: 0.18)]),
            SCNAction.removeFromParentNode()]))
    }

    private func scheduleRedGodRespawn() {
        guard phase == .night else { return }
        redGodRespawnTimer = config.redGodRespawnDelay
    }

    private func enemyAttacksPlayer(_ e: Enemy) {
        let isWolf = e.kind == "wolf" || e.kind == "angryWolf"
        var dmg = Float(e.damage) * config.damageTaken
        if isWolf && hasWolfCover { dmg *= 0.5 }
        changeLives(-Int(dmg.rounded()))
        // knock the attacker away / remove it
        if e.kind == "redgod" {
            defeatEnemyToRespawn(e)
        } else {
            removeEnemyNode(e)
        }
    }

    private func defeatEnemyToRespawn(_ e: Enemy) {
        guard let idx = enemies.firstIndex(where: { $0 === e }) else { return }
        enemies.remove(at: idx)
        e.node.removeAllActions()
        e.node.removeFromParentNode()
        scheduleRedGodRespawn()
    }

    private func removeEnemyNode(_ e: Enemy) {
        guard let idx = enemies.firstIndex(where: { $0 === e }) else { return }
        enemies.remove(at: idx)
        e.node.removeAllActions()
        e.node.removeFromParentNode()
    }

    private func clearEnemies() {
        redGodRespawnTimer = nil
        for e in enemies { e.node.removeFromParentNode() }
        enemies.removeAll()
        for n in scene.rootNode.childNodes where n.name == "dead" { n.removeFromParentNode() }
    }

    // MARK: - Enemy AI (chase the player)
    private func updateEnemies(_ dt: TimeInterval) {
        let p = playerNode.position
        for e in enemies {
            let pos = e.node.position
            let dx = p.x - pos.x
            let dz = p.z - pos.z
            let dist = sqrt(dx * dx + dz * dz)
            if dist <= attackRange {
                enemyAttacksPlayer(e)
                continue
            }
            let step = e.speed * Float(dt)
            e.node.position = SCNVector3(pos.x + dx / dist * step, pos.y, pos.z + dz / dist * step)
            e.node.eulerAngles.y = atan2(dx, dz)
        }
    }

    private func campfireTick(_ dt: TimeInterval) {
        guard phase == .night, let fire = campfireNode else { return }
        campfireAoeAccumulator += dt
        guard campfireAoeAccumulator >= 1.0 else { return }
        campfireAoeAccumulator = 0
        let radius = 3.0 + Float(campfireLevel) * 1.3
        for e in enemies where xzDistance(e.node.position, fire.position) <= radius {
            e.hp -= config.campfireDamage
            if e.hp <= 0 { defeatEnemy(e, byPlayer: false) }
        }
    }

    private func hungerTick(_ dt: TimeInterval) {
        guard food <= 0 else { hungerAccumulator = 0; return }
        hungerAccumulator += dt
        if hungerAccumulator >= 3.0 {
            hungerAccumulator = 0
            floatText("Starving!", color: .red)
            changeLives(-5)
        }
    }

    private func endNight() {
        clearEnemies()
        if day >= maxDays { win(); return }
        day += 1
        startDay()
    }

    // MARK: - Trees / rocks
    private func gatherBonus() -> Int { hasBag ? 1 : 0 }

    private func chopTree(_ tree: SCNNode) {
        guard let remaining = treeChops[tree], remaining > 0 else { return }
        let gain = 1 + (hasAxe ? 1 : 0) + gatherBonus()
        wood += gain
        let left = remaining - 1
        treeChops[tree] = left
        floatText("+\(gain)🪵", color: SKColor(red: 0.8, green: 0.6, blue: 0.3, alpha: 1))
        tree.runAction(SCNAction.sequence([
            SCNAction.rotateBy(x: 0, y: 0, z: 0.12, duration: 0.05),
            SCNAction.rotateBy(x: 0, y: 0, z: -0.12, duration: 0.05)]))
        updateHUD()
        if left <= 0 { depleteResource(tree) }
    }

    private func mineRock(_ rock: SCNNode) {
        guard let remaining = rockMetal[rock], remaining > 0 else { return }
        let gain = 1 + gatherBonus()
        metal += gain
        let left = remaining - 1
        rockMetal[rock] = left
        floatText("+\(gain)🔩", color: SKColor(white: 0.85, alpha: 1))
        rock.runAction(SCNAction.sequence([
            SCNAction.rotateBy(x: 0.08, y: 0, z: 0, duration: 0.05),
            SCNAction.rotateBy(x: -0.08, y: 0, z: 0, duration: 0.05)]))
        updateHUD()
        if left <= 0 { depleteResource(rock) }
    }

    private func depleteResource(_ node: SCNNode) {
        // Only the visual shrink/hide runs via SCNAction (it touches the node,
        // not game state). The 18s regrow is handled on the main game loop.
        node.runAction(SCNAction.sequence([
            SCNAction.scale(to: 0.05, duration: 0.3),
            SCNAction.run { n in n.isHidden = true }]))
        regrowTimers[node] = 18.0
    }

    private func restoreResource(_ node: SCNNode) {
        node.isHidden = false
        node.scale = SCNVector3(1, 1, 1)
        if treeChops[node] != nil {
            node.eulerAngles = SCNVector3Zero
            treeChops[node] = 4
        } else if rockMetal[node] != nil {
            rockMetal[node] = 4
        }
    }

    private func regrowAllTrees() {
        for (tree, _) in treeChops {
            tree.removeAllActions()
            tree.isHidden = false
            tree.scale = SCNVector3(1, 1, 1)
            tree.eulerAngles = SCNVector3Zero
            treeChops[tree] = 4
            regrowTimers[tree] = nil
        }
    }

    private func regrowAllRocks() {
        for (rock, _) in rockMetal {
            rock.removeAllActions()
            rock.isHidden = false
            rock.scale = SCNVector3(1, 1, 1)
            rockMetal[rock] = 4
            regrowTimers[rock] = nil
        }
    }

    // MARK: - Kids / treasures
    private func rescueKid(_ kid: SCNNode) {
        guard let idx = kidNodes.firstIndex(of: kid) else { return }
        kidNodes.remove(at: idx)
        kidsSaved += 1
        changeLives(20)
        flashBanner("🧒 Kid saved! (\(kidsSaved)/4)", color: .green)
        kid.removeAllActions()
        kid.childNode(withName: "marker", recursively: false)?.removeFromParentNode()
        kid.runAction(SCNAction.sequence([
            SCNAction.move(to: SCNVector3(0, 0, 12), duration: 1.2),
            SCNAction.fadeOut(duration: 0.3),
            SCNAction.removeFromParentNode()]))
        updateHUD()
    }

    private func openTreasure(_ chest: SCNNode) {
        guard let idx = treasureNodes.firstIndex(of: chest) else { return }
        treasureNodes.remove(at: idx)
        chest.childNode(withName: "marker", recursively: false)?.removeFromParentNode()
        grantTreasureReward()
        chest.runAction(SCNAction.sequence([
            SCNAction.group([SCNAction.scale(to: 1.4, duration: 0.2),
                             SCNAction.fadeOut(duration: 0.3)]),
            SCNAction.removeFromParentNode()]))
    }

    private func grantTreasureReward() {
        // Prefer giving an unowned tool; otherwise resources.
        var options: [() -> Void] = []
        if !hasKatana { options.append { self.hasKatana = true; self.attackPower += 2; self.flashBanner("💰 Found a Katana! +2 atk", color: .yellow) } }
        if !hasAxe { options.append { self.hasAxe = true; self.flashBanner("💰 Found an Axe!", color: .yellow) } }
        if !hasBag { options.append { self.hasBag = true; self.flashBanner("💰 Found a Bag!", color: .yellow) } }
        if options.isEmpty {
            let r = Int.random(in: 0..<4)
            switch r {
            case 0: food += 6; flashBanner("💰 +6 🍖", color: .yellow)
            case 1: wood += 6; flashBanner("💰 +6 🪵", color: .yellow)
            case 2: metal += 4; flashBanner("💰 +4 🔩", color: .yellow)
            default: changeLives(25); flashBanner("💰 +25 ❤️", color: .yellow)
            }
        } else {
            options.randomElement()?()
        }
        updateHUD()
        updateCraftLabels()
    }

    private func resetKidsAndTreasures() {
        // Rebuild kids
        for k in kidNodes { k.removeFromParentNode() }
        kidNodes.removeAll()
        for n in scene.rootNode.childNodes where n.name == "kid" { n.removeFromParentNode() }
        buildKids()
        // Rebuild treasures
        for t in treasureNodes { t.removeFromParentNode() }
        treasureNodes.removeAll()
        for n in scene.rootNode.childNodes where n.name == "treasure" { n.removeFromParentNode() }
        buildTreasures()
    }

    // MARK: - Merchant
    private func tradeWithMerchant() {
        if !hasWolfCover {
            if bunnyFeet >= 1 {
                bunnyFeet -= 1
                hasWolfCover = true
                flashBanner("🧥 Wolf cover! Wolf bites halved", color: .green)
            } else {
                floatText("Trader wants 1🐾 bunny foot", color: .white)
            }
        } else if bunnyFeet >= 2 {
            bunnyFeet -= 2
            metal += 2
            floatText("Traded 2🐾 → +2🔩", color: .green)
        } else {
            floatText("Trader: bring me 🐾 feet", color: .white)
        }
        updateHUD()
    }

    // MARK: - Campfire
    private func updateCampfireVisual() {
        let s = 0.7 + Float(campfireLevel) * 0.28
        flameNode?.scale = SCNVector3(s, s, s)
        let base: CGFloat = phase == .night ? 350 : 120
        campLight?.intensity = base + CGFloat(campfireLevel) * 220
        campLight?.attenuationEndDistance = CGFloat(8 + campfireLevel * 3)
        applyWorldScale()
        updateCampfireBar()
    }

    private func feedCampfire() {
        if campfireLevel >= maxCampfireLevel { floatText("Fire maxed!", color: .orange); return }
        let cost = campfireLevel * 4
        if wood >= cost {
            wood -= cost
            campfireLevel += 1
            updateCampfireVisual()
            floatText("🔥 Fire Lv \(campfireLevel)!", color: .orange)
            campfireNode?.runAction(SCNAction.sequence([
                SCNAction.scale(to: 1.2, duration: 0.12), SCNAction.scale(to: 1.0, duration: 0.12)]))
            updateHUD()
        } else {
            floatText("Need \(cost)🪵", color: .red)
        }
    }

    // MARK: - Crafting
    private func openCraftMenu() {
        craftingMenuOpen = true
        updateCraftLabels()
        craftMenu.isHidden = false
        moveVec = .zero
        resetJoystickKnob()
    }

    private func closeCraftMenu() {
        craftingMenuOpen = false
        craftMenu.isHidden = true
    }

    private func canAfford(woodCost: Int, metalCost: Int) -> Bool {
        if wood >= woodCost && metal >= metalCost {
            wood -= woodCost; metal -= metalCost
            updateHUD()
            return true
        }
        floatText("Need \(woodCost)🪵 \(metalCost)🔩", color: .red)
        return false
    }

    private func craftKatana() {
        if hasKatana { return }
        if canAfford(woodCost: 6, metalCost: 5) {
            hasKatana = true; attackPower += 2
            floatText("🗡 Katana! atk \(attackPower)", color: .green)
            updateHUD(); updateCraftLabels()
        }
    }

    private func craftAxe() {
        if hasAxe { return }
        if canAfford(woodCost: 4, metalCost: 3) {
            hasAxe = true
            floatText("🪓 Axe crafted!", color: .green)
            updateCraftLabels()
        }
    }

    private func craftBag() {
        if hasBag { return }
        if canAfford(woodCost: 5, metalCost: 2) {
            hasBag = true
            floatText("🎒 Bag crafted!", color: .green)
            updateCraftLabels()
        }
    }

    private func craftBed() {
        if hasBed { return }
        if canAfford(woodCost: 10, metalCost: 4) {
            hasBed = true
            placeBed()
            floatText("🛏 Bed built by the house", color: .green)
            updateCraftLabels()
        }
    }

    private func placeBed() {
        let bed = SCNNode()
        bed.name = "bed"
        let frame = SCNBox(width: 1.2, height: 0.3, length: 2.2, chamferRadius: 0.05)
        frame.firstMaterial?.diffuse.contents = UIColor(red: 0.5, green: 0.33, blue: 0.18, alpha: 1)
        let frameNode = SCNNode(geometry: frame)
        frameNode.position = SCNVector3(0, 0.3, 0)
        bed.addChildNode(frameNode)
        let mattress = SCNBox(width: 1.1, height: 0.25, length: 1.6, chamferRadius: 0.1)
        mattress.firstMaterial?.diffuse.contents = UIColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1)
        let mNode = SCNNode(geometry: mattress)
        mNode.position = SCNVector3(0, 0.55, 0.2)
        bed.addChildNode(mNode)
        let pillow = SCNBox(width: 0.9, height: 0.2, length: 0.4, chamferRadius: 0.08)
        pillow.firstMaterial?.diffuse.contents = UIColor.white
        let pNode = SCNNode(geometry: pillow)
        pNode.position = SCNVector3(0, 0.6, -0.7)
        bed.addChildNode(pNode)
        bed.position = SCNVector3(-2.5, 0, 9.5)
        scene.rootNode.addChildNode(bed)
        bedNode = bed
    }

    private func useBed() {
        if bedUsedToday { floatText("Already rested today", color: .white); return }
        bedUsedToday = true
        changeLives(30)
        floatText("🛏 Rested +30 ❤️", color: .green)
    }

    private func craftMap() {
        if hasMap { return }
        if canAfford(woodCost: 6, metalCost: 2) {
            hasMap = true
            addMapMarkers()
            floatText("🗺 Map reveals kids & treasure", color: .green)
            updateCraftLabels()
        }
    }

    private func addMapMarkers() {
        for kid in kidNodes { addMarker(to: kid, color: .green, height: 2.2) }
        for chest in treasureNodes { addMarker(to: chest, color: .yellow, height: 1.4) }
    }

    private func addMarker(to node: SCNNode, color: UIColor, height: Float) {
        if node.childNode(withName: "marker", recursively: false) != nil { return }
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.3, height: 0.6)
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color
        cone.materials = [mat]
        let marker = SCNNode(geometry: cone)
        marker.name = "marker"
        marker.eulerAngles.x = Float.pi
        marker.position = SCNVector3(0, height + 1.0, 0)
        marker.runAction(.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.3, z: 0, duration: 0.6),
            .moveBy(x: 0, y: -0.3, z: 0, duration: 0.6)])))
        node.addChildNode(marker)
    }

    // MARK: - Lives / win / lose
    private func changeLives(_ delta: Int) {
        lives = min(maxLives, lives + delta)
        if delta < 0 { flashDamage() }
        updateHUD()
        if lives <= 0 { gameOver() }
    }

    private func gameOver() {
        guard phase != .gameOver else { return }
        phase = .gameOver
        removeAllBunnies()
        clearEnemies()
        closeCraftMenu()
        setJoystickVisible(false)
        updateHUD()
        overlay.isHidden = false
        difficultyButtons.isHidden = true
        authorLabel.isHidden = true
        overlayTitle.fontSize = 38
        overlayTitle.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 + 40)
        overlayTitle.text = "YOU DIED"
        overlaySub.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 - 80)
        overlaySub.text = "Fell on day \(day) (\(config.name)). Kids saved: \(kidsSaved)/4.\n\nTap to choose difficulty."
    }

    private func win() {
        phase = .win
        clearEnemies()
        setJoystickVisible(false)
        updateHUD()
        overlay.isHidden = false
        difficultyButtons.isHidden = true
        authorLabel.isHidden = true
        overlayTitle.fontSize = 36
        overlayTitle.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 + 40)
        overlayTitle.text = "YOU SURVIVED!"
        let kidLine = kidsSaved >= 4 ? "All 4 kids saved! 🎉" : "Kids saved: \(kidsSaved)/4."
        overlaySub.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 - 80)
        overlaySub.text = "99 days on \(config.name)! \(kidLine)\n\nTap to play again."
    }

    // MARK: - HUD effects
    private func flashBanner(_ text: String, color: SKColor) {
        let banner = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        banner.text = text
        banner.fontSize = 24
        banner.fontColor = color
        banner.position = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.66)
        banner.zPosition = 150
        banner.setScale(0.6)
        hud.addChild(banner)
        banner.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.0, duration: 0.25), SKAction.fadeIn(withDuration: 0.2)]),
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeOut(withDuration: 0.4)])) { [weak self] in
            self?.removeOverlayNodeSafely(banner)
        }
    }

    private func floatText(_ text: String, color: SKColor) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = 22
        label.fontColor = color
        label.position = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.44)
        label.zPosition = 120
        hud.addChild(label)
        label.run(SKAction.group([SKAction.moveBy(x: 0, y: 60, duration: 0.6),
                                  SKAction.fadeOut(withDuration: 0.6)])) { [weak self] in
            self?.removeOverlayNodeSafely(label)
        }
    }

    /// Removes an overlay SpriteKit node on the main run loop.
    ///
    /// The HUD is an `overlaySKScene`, so its `SKAction`s are stepped during the
    /// SceneKit render pass. Removing a node there runs outside a valid UIKit
    /// CATransaction, and the focus engine's `_focusEnvironmentWillDisappear`
    /// then asserts in `_performAfterCATransactionCommits...` (crash on iPad).
    /// Deferring the removal to the next main run-loop turn gives it a valid
    /// transaction context and avoids the crash.
    private func removeOverlayNodeSafely(_ node: SKNode) {
        DispatchQueue.main.async { node.removeFromParent() }
    }

    private func flashDamage() {
        damageFlash?.removeAllActions()
        damageFlash?.alpha = 0
        damageFlash?.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.45, duration: 0.06),
            SKAction.fadeAlpha(to: 0, duration: 0.25)]))
    }

    // MARK: - Game loop
    private func startTimer() {
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard phase == .day || phase == .night else { return }
        updatePlayer(dt)
        updateEnemies(dt)
        updateSpawning(dt)
        updateRegrow(dt)
        campfireTick(dt)
        hungerTick(dt)
        phaseTimeRemaining -= dt
        updateHUD()
        if phaseTimeRemaining <= 0 {
            if phase == .day { endDay() } else if phase == .night { endNight() }
        }
    }

    private func updateSpawning(_ dt: TimeInterval) {
        if phase == .day {
            daySpawnTimer -= dt
            if daySpawnTimer <= 0 {
                spawnDayCreature()
                resetDaySpawnTimer()
            }
        } else if phase == .night {
            nightSpawnTimer -= dt
            if nightSpawnTimer <= 0 {
                spawnNightCreature()
                resetNightSpawnTimer()
            }
            if var t = redGodRespawnTimer {
                t -= dt
                if t <= 0 {
                    redGodRespawnTimer = nil
                    spawnRedGod()
                } else {
                    redGodRespawnTimer = t
                }
            }
        }
    }

    private func updateRegrow(_ dt: TimeInterval) {
        guard !regrowTimers.isEmpty else { return }
        for (node, time) in Array(regrowTimers) {
            let nt = time - dt
            if nt <= 0 {
                regrowTimers[node] = nil
                restoreResource(node)
            } else {
                regrowTimers[node] = nt
            }
        }
    }

    private func updatePlayer(_ dt: TimeInterval) {
        guard !craftingMenuOpen else { return }
        let vx = Float(moveVec.dx) * playerSpeed
        let vz = -Float(moveVec.dy) * playerSpeed
        if abs(vx) < 0.001 && abs(vz) < 0.001 { return }
        var p = playerNode.position
        p.x = min(maxX, max(minX, p.x + vx * Float(dt)))
        p.z = min(maxZ, max(minZ, p.z + vz * Float(dt)))
        playerNode.position = p
        playerNode.eulerAngles.y = atan2(vx, vz)
    }

    // MARK: - Input
    func joystickContains(viewPoint: CGPoint) -> Bool {
        let p = hud.convertPoint(fromView: viewPoint)
        return hypot(p.x - joystickCenter.x, p.y - joystickCenter.y) <= joystickActivation
    }

    func joystickBegin(viewPoint: CGPoint) { joystickMove(viewPoint: viewPoint) }

    func joystickMove(viewPoint: CGPoint) {
        let p = hud.convertPoint(fromView: viewPoint)
        var dx = p.x - joystickCenter.x
        var dy = p.y - joystickCenter.y
        let dist = hypot(dx, dy)
        if dist > joystickRadius { dx = dx / dist * joystickRadius; dy = dy / dist * joystickRadius }
        joystickKnob.position = CGPoint(x: joystickCenter.x + dx, y: joystickCenter.y + dy)
        moveVec = CGVector(dx: dx / joystickRadius, dy: dy / joystickRadius)
    }

    func joystickEnd() { moveVec = .zero; resetJoystickKnob() }
    private func resetJoystickKnob() { joystickKnob.position = joystickCenter }

    func handleTap(at viewPoint: CGPoint, in view: SCNView) {
        switch phase {
        case .title:
            let hp = hud.convertPoint(fromView: viewPoint)
            for node in hud.nodes(at: hp) {
                if let name = node.name, name.hasPrefix("diff_"),
                   let raw = Int(name.dropFirst(5)), let diff = Difficulty(rawValue: raw) {
                    startGame(diff); return
                }
            }
            return
        case .gameOver, .win:
            showTitle(); return
        case .day, .night:
            break
        }

        if craftingMenuOpen {
            let hp = hud.convertPoint(fromView: viewPoint)
            for node in hud.nodes(at: hp) {
                switch node.name {
                case "craft_katana": craftKatana(); return
                case "craft_axe": craftAxe(); return
                case "craft_bag": craftBag(); return
                case "craft_bed": craftBed(); return
                case "craft_map": craftMap(); return
                case "craft_close": closeCraftMenu(); return
                default: break
                }
            }
            return
        }

        guard let target = gameNode(from: view.hitTest(viewPoint, options: nil)) else { return }
        switch target.name {
        case "bunny":
            killBunny(target)
        case "wolf", "angryWolf", "demon", "redgod":
            if let e = enemy(for: target) { hitEnemy(e) }
        case "tree":
            interactIfNear(target, "tree") { self.chopTree(target) }
        case "rock":
            interactIfNear(target, "rock") { self.mineRock(target) }
        case "campfire":
            interactIfNear(target, "fire") { self.feedCampfire() }
        case "crafttable":
            interactIfNear(target, "table") { self.openCraftMenu() }
        case "merchant":
            interactIfNear(target, "trader") { self.tradeWithMerchant() }
        case "kid":
            interactIfNear(target, "kid") { self.rescueKid(target) }
        case "treasure":
            interactIfNear(target, "treasure") { self.openTreasure(target) }
        case "bed":
            interactIfNear(target, "bed") { self.useBed() }
        default:
            break
        }
    }

    private func interactIfNear(_ node: SCNNode, _ label: String, _ action: () -> Void) {
        if isNearPlayer(node) { action() }
        else { floatText("Too far from \(label)", color: .white) }
    }

    private func gameNode(from hits: [SCNHitTestResult]) -> SCNNode? {
        let names: Set<String> = ["bunny", "wolf", "angryWolf", "demon", "redgod",
                                  "tree", "rock", "campfire", "crafttable",
                                  "merchant", "kid", "treasure", "bed"]
        for hit in hits {
            var node: SCNNode? = hit.node
            while let cur = node {
                if let name = cur.name, names.contains(name) { return cur }
                node = cur.parent
            }
        }
        return nil
    }

    private func isNearPlayer(_ node: SCNNode) -> Bool {
        xzDistance(node.position, playerNode.position) <= interactRange
    }

    private func xzDistance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return sqrt(dx * dx + dz * dz)
    }
}
