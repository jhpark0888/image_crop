part of image_crop;

const _kCropGridColumnCount = 3;
const _kCropGridRowCount = 3;
const _kCropGridColor = Color.fromRGBO(0xd0, 0xd0, 0xd0, 0.9);
const _kCropOverlayActiveOpacity = 0.3;
const _kCropOverlayInactiveOpacity = 0.7;

enum _CropAction { none, moving, scaling }

class Crop extends StatefulWidget {
  final ImageProvider image;
  final double? aspectRatio;
  final double? width;
  final double? height;
  final double maximumScale;
  final bool alwaysShowGrid;
  final bool circleShape;
  final bool isExpandImageInit;
  final double? maxCropAspectRatio;
  final double? minCropAspectRatio;
  final Color gridColor;
  final ImageErrorListener? onImageError;
  final Widget Function(bool isExpanded)? resizeButtonBuilder;

  const Crop({
    Key? key,
    required this.image,
    this.aspectRatio,
    this.maximumScale = 2.0,
    this.width,
    this.height,
    this.alwaysShowGrid = false,
    this.circleShape = false,
    this.isExpandImageInit = false,
    this.maxCropAspectRatio,
    this.minCropAspectRatio,
    this.resizeButtonBuilder,
    this.gridColor = _kCropGridColor,
    this.onImageError,
  }) : super(key: key);

  Crop.file(
    File file, {
    Key? key,
    double scale = 1.0,
    this.aspectRatio,
    this.width,
    this.height,
    this.maximumScale = 2.0,
    this.alwaysShowGrid = false,
    this.circleShape = false,
    this.isExpandImageInit = false,
    this.maxCropAspectRatio,
    this.minCropAspectRatio,
    this.resizeButtonBuilder,
    this.gridColor = _kCropGridColor,
    this.onImageError,
  })  : image = FileImage(file, scale: scale),
        super(key: key);

  Crop.asset(
    String assetName, {
    Key? key,
    AssetBundle? bundle,
    String? package,
    this.aspectRatio,
    this.width,
    this.height,
    this.maximumScale = 2.0,
    this.alwaysShowGrid = false,
    this.circleShape = false,
    this.isExpandImageInit = false,
    this.maxCropAspectRatio,
    this.minCropAspectRatio,
    this.resizeButtonBuilder,
    this.gridColor = _kCropGridColor,
    this.onImageError,
  })  : image = AssetImage(assetName, bundle: bundle, package: package),
        super(key: key);

  @override
  State<StatefulWidget> createState() => CropState();

  static CropState? of(BuildContext context) =>
      context.findAncestorStateOfType<CropState>();
}

class CropState extends State<Crop> with TickerProviderStateMixin {
  final _surfaceKey = GlobalKey();

  late final AnimationController _activeController;
  late final AnimationController _settleController;

  double maxCropAspectRatio = 1;
  double minCropAspectRatio = 1;
  bool showResizeButton = false;

  double _scale = 1.0;
  double _ratio = 1.0;
  double _imageAspectRatio = 1.0;

  Rect _view = Rect.zero;
  Rect _area = Rect.zero;
  Offset _lastFocalPoint = Offset.zero;
  _CropAction _action = _CropAction.none;

  late double _startScale;
  late Rect _startView;
  late Tween<Rect?> _viewTween;
  late Tween<double> _scaleTween;

  ImageStream? _imageStream;
  ui.Image? _image;
  ImageStreamListener? _imageListener;

  double get scale => _scale;
  bool get _isExpanded => _scale >= 1.0;

  set scale(double scale) {
    _scale = scale;
    _handleScaleEnd(ScaleEndDetails());
  }

  Rect? get area => _view.isEmpty
      ? null
      : Rect.fromLTWH(
          _area.left * _view.width / _scale - _view.left,
          _area.top * _view.height / _scale - _view.top,
          _area.width * _view.width / _scale,
          _area.height * _view.height / _scale,
        );

  Rect get view => _view;

  set view(Rect view) {
    _view = view;
    _handleScaleEnd(ScaleEndDetails());
  }

  bool get _isEnabled => _view.isEmpty == false && _image != null;

  // Saving the length for the widest area for different aspectRatio's
  final Map<double, double> _maxAreaWidthMap = {};

  // Counting pointers(number of user fingers on screen)
  int pointers = 0;

  @override
  void initState() {
    super.initState();

    _activeController = AnimationController(
      vsync: this,
      value: widget.alwaysShowGrid ? 1.0 : 0.0,
    )..addListener(() => setState(() {}));
    _settleController = AnimationController(vsync: this)
      ..addListener(_settleAnimationChanged);

    if (widget.maxCropAspectRatio != null) {
      maxCropAspectRatio = widget.maxCropAspectRatio!;
    }

    if (widget.minCropAspectRatio != null) {
      minCropAspectRatio = widget.minCropAspectRatio!;
    }

    checkShowResizeButton();
  }

  @override
  void dispose() {
    final listener = _imageListener;
    if (listener != null) {
      _imageStream?.removeListener(listener);
    }
    _activeController.dispose();
    _settleController.dispose();

    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _getImage();
    });
  }

  @override
  void didUpdateWidget(Crop oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.image != oldWidget.image) {
      _getImage();
    } else if (widget.aspectRatio != oldWidget.aspectRatio) {
      _area = _calculateArea(
        viewWidth: _view.width,
        viewHeight: _view.height,
        imageWidth: _image?.width,
        imageHeight: _image?.height,
      );
    }
    if (widget.alwaysShowGrid != oldWidget.alwaysShowGrid) {
      if (widget.alwaysShowGrid) {
        _activate();
      } else {
        _deactivate();
      }
    }
  }

  void _getImage({bool force = false}) {
    final oldImageStream = _imageStream;
    final newImageStream =
        widget.image.resolve(createLocalImageConfiguration(context));
    _imageStream = newImageStream;
    if (newImageStream.key != oldImageStream?.key || force) {
      final oldImageListener = _imageListener;
      if (oldImageListener != null) {
        oldImageStream?.removeListener(oldImageListener);
      }
      final newImageListener =
          ImageStreamListener(_updateImage, onError: widget.onImageError);
      _imageListener = newImageListener;
      newImageStream.addListener(newImageListener);
    }
  }

  void setMaxSizeArea() {
    if (_boundaries == null) return;
    if (_image == null) return;

    _area = _calculateArea(
      viewWidth: _view.width,
      viewHeight: _view.height,
      imageWidth: _image!.width,
      imageHeight: _image!.height,
    );

    _scale = 1.0;
    _view = Rect.fromLTWH(
      (_view.width - 1.0) / 2,
      (_view.height - 1.0) / 2,
      _view.width,
      _view.height,
    );
  }

  void setMinSizeArea() {
    if (_boundaries == null) return;
    if (_image == null) return;

    _area = _calculateArea(
      viewWidth: _view.width,
      viewHeight: _view.height,
      imageWidth: _image!.width,
      imageHeight: _image!.height,
      imageAspectRatio:
          _imageAspectRatio > 1.0 ? maxCropAspectRatio : minCropAspectRatio,
    );

    _scale = _minimumScale ?? _scale;
    _view = _getViewInBoundaries(_scale);
  }

  void resizeArea() {
    setState(() {
      if (_isExpanded) {
        setMinSizeArea();
      } else {
        setMaxSizeArea();
      }
    });
  }

  Widget _buildReSizeButton() {
    return RawGestureDetector(
      gestures: {
        _EagerTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_EagerTapGestureRecognizer>(
                () => _EagerTapGestureRecognizer(),
                (_EagerTapGestureRecognizer instance) {
          instance.onTap = resizeArea;
        }),
      },
      child: widget.resizeButtonBuilder?.call(_isExpanded) ??
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white.withOpacity(0.8),
            ),
            child: Icon(
              _isExpanded
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              size: 30,
            ),
          ),
    );
  }

  void checkShowResizeButton() {
    if (maxCropAspectRatio != 1 || minCropAspectRatio != 1) {
      showResizeButton = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width ?? MediaQuery.of(context).size.width,
      height: widget.height ?? MediaQuery.of(context).size.width,
      child: Listener(
        onPointerDown: (event) => pointers++,
        onPointerUp: (event) => pointers = 0,
        child: RawGestureDetector(
          key: _surfaceKey,
          behavior: HitTestBehavior.opaque,
          gestures: {
            _EagerScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                _EagerScaleGestureRecognizer>(
              () => _EagerScaleGestureRecognizer(),
              (_EagerScaleGestureRecognizer instance) {
                instance
                  ..onStart = _handleScaleStart
                  ..onUpdate = _handleScaleUpdate
                  ..onEnd = _handleScaleEnd;
              },
            ),
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CropPainter(
                    image: _image,
                    ratio: _ratio,
                    view: _view,
                    area: _area,
                    scale: _scale,
                    active: _activeController.value,
                    gridColor: widget.gridColor,
                    circleShape: widget.circleShape,
                  ),
                ),
              ),
              if (showResizeButton)
                Positioned(
                  left: 20,
                  bottom: 20,
                  child: _buildReSizeButton(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _activate() {
    _activeController.animateTo(
      1.0,
      curve: Curves.fastOutSlowIn,
      duration: const Duration(milliseconds: 250),
    );
  }

  void _deactivate() {
    if (widget.alwaysShowGrid == false) {
      _activeController.animateTo(
        0.0,
        curve: Curves.fastOutSlowIn,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  Size? get _boundaries {
    final context = _surfaceKey.currentContext;
    if (context == null) {
      return null;
    }

    final size = context.size;
    if (size == null) {
      return null;
    }

    return size;
  }

  Offset? _getLocalPoint(Offset point) {
    final context = _surfaceKey.currentContext;
    if (context == null) {
      return null;
    }

    final box = context.findRenderObject() as RenderBox;

    return box.globalToLocal(point);
  }

  void _settleAnimationChanged() {
    setState(() {
      _scale = _scaleTween.transform(_settleController.value);
      final nextView = _viewTween.transform(_settleController.value);
      if (nextView != null) {
        _view = nextView;
      }
    });
  }

  Rect _calculateArea({
    required int? imageWidth,
    required int? imageHeight,
    required double viewWidth,
    required double viewHeight,
    double? imageAspectRatio,
  }) {
    if (imageWidth == null || imageHeight == null) {
      return Rect.zero;
    }

    final double aspectRatioValue =
        imageAspectRatio ?? widget.aspectRatio ?? 1.0;

    double height;
    double width;
    if (aspectRatioValue < 1) {
      height = 1.0;
      width = (aspectRatioValue * imageHeight * viewHeight * height) /
          imageWidth /
          viewWidth;
      if (width > 1.0) {
        width = 1.0;
        height = (imageWidth * viewWidth * width) /
            (imageHeight * viewHeight * aspectRatioValue);
      }
    } else {
      width = 1.0;
      height = (imageWidth * viewWidth * width) /
          (imageHeight * viewHeight * aspectRatioValue);
      if (height > 1.0) {
        height = 1.0;
        width = (aspectRatioValue * imageHeight * viewHeight * height) /
            imageWidth /
            viewWidth;
      }
    }
    final aspectRatio = _maxAreaWidthMap[aspectRatioValue];
    if (aspectRatio != null) {
      _maxAreaWidthMap[aspectRatio] = width;
    }

    return Rect.fromLTWH((1.0 - width) / 2, (1.0 - height) / 2, width, height);
  }

  void _updateImage(ImageInfo imageInfo, bool synchronousCall) {
    final boundaries = _boundaries;

    if (boundaries == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final image = imageInfo.image;

      // 이미지 비율만큼 최소 또는 최대 비율 조정
      _imageAspectRatio = image.width / image.height;
      if (widget.maxCropAspectRatio == null && _imageAspectRatio > 1.0) {
        maxCropAspectRatio = _imageAspectRatio;
      }

      if (widget.minCropAspectRatio == null && _imageAspectRatio <= 1.0) {
        minCropAspectRatio = _imageAspectRatio;
      }

      checkShowResizeButton();

      setState(() {
        _image = image;
        _scale = imageInfo.scale;
        _ratio = max(
          boundaries.width / image.width,
          boundaries.height / image.height,
        );

        final viewWidth = boundaries.width / (image.width * _scale * _ratio);
        final viewHeight = boundaries.height / (image.height * _scale * _ratio);

        // 처음 이미지를 선택 했을 때의 이미지 비율
        double imageAspectRatio = widget.isExpandImageInit
            // 영역에 맞게 확장
            ? 1
            // 이미지 비율 만큼
            : _imageAspectRatio > 1.0
                ? maxCropAspectRatio
                : minCropAspectRatio;

        _area = _calculateArea(
          viewWidth: viewWidth,
          viewHeight: viewHeight,
          imageWidth: image.width,
          imageHeight: image.height,
          // 이미지 비율 만큼 _area를 맞추는 로직
          imageAspectRatio: imageAspectRatio,
        );

        _view = Rect.fromLTWH(
          (viewWidth - 1.0) / 2,
          (viewHeight - 1.0) / 2,
          viewWidth,
          viewHeight,
        );

        // 이미지 사이즈 만큼 _view를 맞추는 로직
        _scale = _minimumScale ?? _scale;
        _view = _getViewInBoundaries(_scale);
      });
    });

    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _activate();
    _settleController.stop(canceled: false);
    _lastFocalPoint = details.focalPoint;
    _action = _CropAction.none;
    _startScale = _scale;
    _startView = _view;
  }

  Rect _getViewInBoundaries(double scale) =>
      Offset(
        max(
          min(
            _view.left,
            _area.left * _view.width / scale,
          ),
          _area.right * _view.width / scale - 1.0,
        ),
        max(
          min(
            _view.top,
            _area.top * _view.height / scale,
          ),
          _area.bottom * _view.height / scale - 1.0,
        ),
      ) &
      _view.size;

  double get _maximumScale => widget.maximumScale;

  double? get _minimumScale {
    final boundaries = _boundaries;
    final image = _image;
    if (boundaries == null || image == null) {
      return null;
    }

    final scaleX = boundaries.width * _area.width / (image.width * _ratio);
    final scaleY = boundaries.height * _area.height / (image.height * _ratio);
    return min(_maximumScale, max(scaleX, scaleY));
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _deactivate();
    final minimumScale = _minimumScale;
    if (minimumScale == null) {
      return;
    }

    final targetScale = _scale.clamp(minimumScale, _maximumScale);
    _scaleTween = Tween<double>(
      begin: _scale,
      end: targetScale,
    );

    _startView = _view;
    _viewTween = RectTween(
      begin: _view,
      end: _getViewInBoundaries(targetScale),
    );

    _settleController.value = 0.0;
    _settleController.animateTo(
      1.0,
      curve: Curves.fastOutSlowIn,
      duration: const Duration(milliseconds: 350),
    );
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_action == _CropAction.none) {
      _action = pointers == 2 ? _CropAction.scaling : _CropAction.moving;
    }

    if (_action == _CropAction.moving) {
      final image = _image;
      if (image == null) {
        return;
      }

      final delta = details.focalPoint - _lastFocalPoint;
      _lastFocalPoint = details.focalPoint;

      setState(() {
        _view = _view.translate(
          delta.dx / (image.width * _scale * _ratio),
          delta.dy / (image.height * _scale * _ratio),
        );
      });
    } else if (_action == _CropAction.scaling) {
      final image = _image;
      final boundaries = _boundaries;
      if (image == null || boundaries == null) {
        return;
      }

      setState(() {
        _scale = _startScale * details.scale;

        final double aspectRatioWithScale = _imageAspectRatio > 1.0
            ? widget.aspectRatio ?? 1.0 * (1 / _scale)
            : widget.aspectRatio ?? 1.0 * _scale;

        double aspectRatio = _imageAspectRatio > 1.0
            ? min(maxCropAspectRatio, max(1.0, aspectRatioWithScale))
            : max(minCropAspectRatio, min(1.0, aspectRatioWithScale));

        final dx = boundaries.width *
            (1.0 - details.scale) /
            (image.width * _scale * _ratio);
        final dy = boundaries.height *
            (1.0 - details.scale) /
            (image.height * _scale * _ratio);

        _view = Rect.fromLTWH(
          _startView.left + dx / 2,
          _startView.top + dy / 2,
          _startView.width,
          _startView.height,
        );

        _area = _calculateArea(
          viewWidth: _view.width,
          viewHeight: _view.height,
          imageWidth: image.width,
          imageHeight: image.height,
          imageAspectRatio: aspectRatio,
        );
      });
    }
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image? image;
  final Rect view;
  final double ratio;
  final Rect area;
  final double scale;
  final double active;
  final bool circleShape;
  final Color gridColor;

  _CropPainter({
    required this.image,
    required this.view,
    required this.ratio,
    required this.area,
    required this.scale,
    required this.active,
    required this.circleShape,
    required this.gridColor,
  });

  @override
  bool shouldRepaint(_CropPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.view != view ||
        oldDelegate.ratio != ratio ||
        oldDelegate.area != area ||
        oldDelegate.active != active ||
        oldDelegate.scale != scale;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height,
    );

    canvas.save();
    canvas.translate(rect.left, rect.top);

    final paint = Paint()..isAntiAlias = false;

    final image = this.image;
    if (image != null) {
      final src = Rect.fromLTWH(
        0.0,
        0.0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = Rect.fromLTWH(
        view.left * image.width * scale * ratio,
        view.top * image.height * scale * ratio,
        image.width * scale * ratio,
        image.height * scale * ratio,
      );

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0.0, 0.0, rect.width, rect.height));
      canvas.drawImageRect(image, src, dst, paint);
      canvas.restore();
    }

    paint.color = Color.fromRGBO(
        0x0,
        0x0,
        0x0,
        _kCropOverlayActiveOpacity * active +
            _kCropOverlayInactiveOpacity * (1.0 - active));
    final boundaries = Rect.fromLTWH(
      rect.width * area.left,
      rect.height * area.top,
      rect.width * area.width,
      rect.height * area.height,
    );
    canvas.drawRect(Rect.fromLTRB(0.0, 0.0, rect.width, boundaries.top), paint);
    canvas.drawRect(
        Rect.fromLTRB(0.0, boundaries.bottom, rect.width, rect.height), paint);
    canvas.drawRect(
        Rect.fromLTRB(0.0, boundaries.top, boundaries.left, boundaries.bottom),
        paint);
    canvas.drawRect(
        Rect.fromLTRB(
            boundaries.right, boundaries.top, rect.width, boundaries.bottom),
        paint);

    if (boundaries.isEmpty == false) {
      _drawGrid(canvas, boundaries);
    }

    if (circleShape) {
      double radius = rect.width / 2;

      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(0, rect.height)
        ..lineTo(rect.width, rect.height)
        ..lineTo(rect.width, 0)
        ..lineTo(0, 0)
        ..moveTo(0, rect.height / 2)
        ..arcToPoint(Offset(rect.width / 2, 0), radius: Radius.circular(radius))
        ..arcToPoint(Offset(rect.width, rect.height / 2),
            radius: Radius.circular(radius))
        ..arcToPoint(Offset(rect.width / 2, rect.height),
            radius: Radius.circular(radius))
        ..arcToPoint(Offset(0, rect.height / 2),
            radius: Radius.circular(radius));

      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Rect boundaries) {
    if (active == 0.0) return;

    final paint = Paint()
      ..isAntiAlias = false
      ..color = gridColor.withOpacity(gridColor.opacity * active)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path()
      ..moveTo(boundaries.left, boundaries.top)
      ..lineTo(boundaries.right, boundaries.top)
      ..lineTo(boundaries.right, boundaries.bottom)
      ..lineTo(boundaries.left, boundaries.bottom)
      ..lineTo(boundaries.left, boundaries.top);

    for (var column = 1; column < _kCropGridColumnCount; column++) {
      path
        ..moveTo(
            boundaries.left + column * boundaries.width / _kCropGridColumnCount,
            boundaries.top)
        ..lineTo(
            boundaries.left + column * boundaries.width / _kCropGridColumnCount,
            boundaries.bottom);
    }

    for (var row = 1; row < _kCropGridRowCount; row++) {
      path
        ..moveTo(boundaries.left,
            boundaries.top + row * boundaries.height / _kCropGridRowCount)
        ..lineTo(boundaries.right,
            boundaries.top + row * boundaries.height / _kCropGridRowCount);
    }

    canvas.drawPath(path, paint);
  }
}

class _EagerScaleGestureRecognizer extends ScaleGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _EagerTapGestureRecognizer extends TapGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}
