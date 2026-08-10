package com.rideatlas.rideatlas.car

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.util.LruCache
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.roundToInt
import kotlin.math.tan

/**
 * Draws a live, heading-up rotating map on the Android Auto surface while a
 * recording is in progress - the car-screen counterpart of RecordScreen's
 * own course-up map (lib/screens/record_screen.dart). Tiles come from the
 * same free Carto Voyager raster source lib/models/base_map_style.dart uses
 * for the phone map, so no API key or billing account is needed. Read-only:
 * no pan/zoom from the car screen - driver-distraction rules keep this to
 * "watch your live position", not a fully interactive map.
 *
 * All drawing happens off the main thread: [renderExecutor] serializes
 * actual Surface locks/draws, [tileExecutor] fetches tiles in parallel
 * without blocking a render pass - a cache miss just draws the background
 * color for that tile and triggers a fresh redraw once the fetch lands.
 */
class CarMapRenderer(private val carContext: CarContext) : SurfaceCallback {
    companion object {
        private const val ZOOM = 16
        private const val TILE_SIZE = 256
        private const val TILE_GRID_RADIUS = 2 // draws a 5x5 tile grid
        private const val TILE_URL =
            "https://a.basemaps.cartocdn.com/rastertiles/voyager/%d/%d/%d.png"
    }

    private val renderExecutor = Executors.newSingleThreadExecutor()
    private val tileExecutor = Executors.newFixedThreadPool(4)
    private val tileCache = LruCache<String, Bitmap>(60)
    private val pendingFetches = mutableSetOf<String>()

    private var surfaceContainer: SurfaceContainer? = null
    private var visibleArea: Rect? = null

    private val trailPaint = Paint().apply {
        color = Color.parseColor("#1976D2")
        style = Paint.Style.STROKE
        strokeWidth = 10f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        isAntiAlias = true
    }
    private val vehicleFillPaint = Paint().apply {
        color = Color.parseColor("#1976D2")
        style = Paint.Style.FILL
        isAntiAlias = true
    }
    private val vehicleOutlinePaint = Paint().apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 4f
        isAntiAlias = true
    }
    private val statsBgPaint = Paint().apply {
        color = Color.parseColor("#CC000000")
        isAntiAlias = true
    }
    private val statsTitlePaint = Paint().apply {
        color = Color.WHITE
        textSize = 56f
        isFakeBoldText = true
        isAntiAlias = true
    }
    private val statsSubPaint = Paint().apply {
        color = Color.parseColor("#E0E0E0")
        textSize = 32f
        isAntiAlias = true
    }

    fun attach() {
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(this)
    }

    override fun onSurfaceAvailable(surfaceContainer: SurfaceContainer) {
        this.surfaceContainer = surfaceContainer
        redraw()
    }

    override fun onSurfaceDestroyed(surfaceContainer: SurfaceContainer) {
        this.surfaceContainer = null
    }

    override fun onVisibleAreaChanged(visibleArea: Rect) {
        this.visibleArea = visibleArea
        redraw()
    }

    fun redraw() {
        val container = surfaceContainer ?: return
        renderExecutor.execute { renderFrame(container) }
    }

    private fun renderFrame(container: SurfaceContainer) {
        val surface = container.surface ?: return
        if (!surface.isValid) return
        val canvas =
            try {
                surface.lockCanvas(null)
            } catch (e: Exception) {
                null
            } ?: return
        try {
            drawFrame(canvas, container)
        } finally {
            try {
                surface.unlockCanvasAndPost(canvas)
            } catch (e: Exception) {
                // Surface may have been torn down mid-draw - nothing to do.
            }
        }
    }

    private fun drawFrame(canvas: Canvas, container: SurfaceContainer) {
        val width = container.width
        val height = container.height
        canvas.drawColor(Color.parseColor("#DDE3E8"))

        val lat = CarRecordingBridge.latitude
        val lng = CarRecordingBridge.longitude
        if (lat != null && lng != null) {
            val heading = CarRecordingBridge.headingDegrees ?: 0.0
            val area = visibleArea
            val cx = if (area != null) area.centerX().toFloat() else width / 2f
            val cy = if (area != null) area.centerY().toFloat() else height / 2f

            val vehicleWorldX = lonToWorldX(lng)
            val vehicleWorldY = latToWorldY(lat)
            val vehicleTileX = floor(vehicleWorldX / TILE_SIZE).toInt()
            val vehicleTileY = floor(vehicleWorldY / TILE_SIZE).toInt()

            canvas.save()
            canvas.translate(cx, cy)
            canvas.rotate(-heading.toFloat())

            for (dx in -TILE_GRID_RADIUS..TILE_GRID_RADIUS) {
                for (dy in -TILE_GRID_RADIUS..TILE_GRID_RADIUS) {
                    val tx = vehicleTileX + dx
                    val ty = vehicleTileY + dy
                    val bmp = tileFor(tx, ty) ?: continue
                    val left = (tx * TILE_SIZE - vehicleWorldX).toFloat()
                    val top = (ty * TILE_SIZE - vehicleWorldY).toFloat()
                    canvas.drawBitmap(bmp, left, top, null)
                }
            }

            val trail = CarRecordingBridge.trailSnapshot()
            if (trail.size >= 2) {
                val path = Path()
                trail.forEachIndexed { index, point ->
                    val wx = (lonToWorldX(point[1]) - vehicleWorldX).toFloat()
                    val wy = (latToWorldY(point[0]) - vehicleWorldY).toFloat()
                    if (index == 0) path.moveTo(wx, wy) else path.lineTo(wx, wy)
                }
                canvas.drawPath(path, trailPaint)
            }

            canvas.restore()

            // Vehicle marker: drawn last, outside the rotated context, so
            // it always points straight up on screen - the map rotates
            // under it, not the other way round (same convention as
            // RecordScreen's own heading cone).
            canvas.save()
            canvas.translate(cx, cy)
            val arrow =
                Path().apply {
                    moveTo(0f, -26f)
                    lineTo(18f, 20f)
                    lineTo(0f, 8f)
                    lineTo(-18f, 20f)
                    close()
                }
            canvas.drawPath(arrow, vehicleFillPaint)
            canvas.drawPath(arrow, vehicleOutlinePaint)
            canvas.restore()
        }

        drawStats(canvas)
    }

    private fun drawStats(canvas: Canvas) {
        val area = visibleArea
        val left = (area?.left ?: 24).toFloat() + 16f
        val top = (area?.top ?: 24).toFloat() + 16f
        val cardWidth = 420f
        val cardHeight = 130f
        canvas.drawRoundRect(
            RectF(left, top, left + cardWidth, top + cardHeight),
            18f,
            18f,
            statsBgPaint,
        )
        val speed = CarRecordingBridge.speedKmh.roundToInt()
        canvas.drawText("$speed km/s", left + 24f, top + 58f, statsTitlePaint)
        val duration = formatDuration(CarRecordingBridge.durationSeconds)
        val distance =
            String.format(Locale.getDefault(), "%.2f km", CarRecordingBridge.distanceKm)
        canvas.drawText("$duration    $distance", left + 24f, top + 102f, statsSubPaint)
    }

    private fun formatDuration(totalSeconds: Int): String {
        val h = totalSeconds / 3600
        val m = (totalSeconds % 3600) / 60
        val s = totalSeconds % 60
        return if (h > 0) {
            String.format(Locale.getDefault(), "%d:%02d:%02d", h, m, s)
        } else {
            String.format(Locale.getDefault(), "%02d:%02d", m, s)
        }
    }

    private fun lonToWorldX(lon: Double): Double {
        val n = (1 shl ZOOM).toDouble()
        return (lon + 180.0) / 360.0 * n * TILE_SIZE
    }

    private fun latToWorldY(lat: Double): Double {
        val n = (1 shl ZOOM).toDouble()
        val latRad = Math.toRadians(lat)
        return (1.0 - ln(tan(latRad) + 1.0 / cos(latRad)) / PI) / 2.0 * n * TILE_SIZE
    }

    /** Cache-or-fetch a tile; returns null (and kicks off a background fetch
     * if one isn't already in flight) on a cache miss, so the render pass
     * itself never blocks on network I/O. */
    private fun tileFor(x: Int, y: Int): Bitmap? {
        val max = 1 shl ZOOM
        val wrappedX = ((x % max) + max) % max
        if (y < 0 || y >= max) return null
        val key = "$wrappedX/$y"
        tileCache.get(key)?.let { return it }
        synchronized(pendingFetches) {
            if (!pendingFetches.add(key)) return null
        }
        tileExecutor.execute {
            try {
                val url = URL(String.format(Locale.US, TILE_URL, ZOOM, wrappedX, y))
                val connection = url.openConnection() as HttpURLConnection
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                val bitmap = connection.inputStream.use { BitmapFactory.decodeStream(it) }
                if (bitmap != null) {
                    tileCache.put(key, bitmap)
                    redraw()
                }
            } catch (e: Exception) {
                // Offline / flaky connection - the next position update
                // triggers a fresh redraw, which retries the fetch since
                // this key is no longer in pendingFetches.
            } finally {
                synchronized(pendingFetches) { pendingFetches.remove(key) }
            }
        }
        return null
    }
}
