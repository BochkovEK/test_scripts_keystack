"""
Glance Image Service monitoring
Checks image statuses and API availability
"""

import time
from config.config import ServiceType
import openstack


class GlanceCheck:
    """
    Glance Image Service health monitoring class.

    Provides monitoring of Glance image service including:
    - API availability and response time
    - Image status breakdown (active / queued / saving / killed / deleted)
    - Detection of stuck or failed images (killed, long-stuck queued/saving)
    """

    # Statuses considered problematic if present
    PROBLEM_STATUSES = ['killed']
    # Statuses considered "in progress" - not necessarily an error, but worth
    # surfacing if there are many of them or debug is enabled
    TRANSIENT_STATUSES = ['queued', 'saving']

    def __init__(self, config, debug=False):
        """
        Initialize Glance health check.

        Args:
            config: Config object providing service authentication
            debug: Enable debug output for troubleshooting
        """
        self.config = config
        self.debug = debug
        auth_params = config.get_service_auth(ServiceType.OPENSTACK)
        self.conn = openstack.connection.Connection(
            **auth_params,
            image_api_version='2'
        )

        if self.debug:
            print(f"🔧 [GLANCE_DEBUG] Initialized with image API v2")

    def display_details(self, data):
        """
        Display Glance image service details in formatted output.

        Args:
            data: Dictionary containing image statistics and status information
        """
        images = data['images']

        print(f"  Images: {images['total']} total")

        if 'by_status' in images:
            for status, count in images['by_status'].items():
                if status in self.PROBLEM_STATUSES:
                    emoji = "🔴"
                elif status in self.TRANSIENT_STATUSES:
                    emoji = "🟡"
                else:
                    emoji = "🟢"

                print(f"    {emoji} {status}: {count}")

        if images.get('problem_images'):
            print(f"  ⚠️  Problem images detected:")
            for img in images['problem_images']:
                print(f"      🔴 {img['name']} ({img['id']}) : {img['status']}")

    def run_check(self):
        """
        Execute Glance image service health check.

        Returns:
            Dictionary containing check results:
            - status: Overall check status ('OK', 'DEGRADED' or 'ERROR')
            - response_time: API response time in seconds
            - images: Detailed image statistics
            - total_images: Total number of discovered images
        """
        start_time = time.time()

        try:
            images = list(self.conn.image.images())

            if self.debug:
                print(f"🔧 [GLANCE_DEBUG] Check started. Retrieved {len(images)} images.")
                if images:
                    img = images[0]
                    print(f"🔧 [GLANCE_DEBUG] Attributes of the first image for debugging:")
                    print(f"    Name      : {getattr(img, 'name', None)}")
                    print(f"    Status    : {getattr(img, 'status', None)}")
                    print(f"    Visibility: {getattr(img, 'visibility', None)}")
                    print(f"    Size      : {getattr(img, 'size', None)}")

            image_stats = self._analyze_images(images)

            if image_stats['problem_images']:
                status = 'DEGRADED'
            else:
                status = 'OK'

            result = {
                'status': status,
                'response_time': round(time.time() - start_time, 2),
                'images': image_stats,
                'total_images': len(images)
            }

            if self.debug:
                print(f"🔧 [GLANCE_DEBUG] Check completed: {len(images)} images processed")

            return result

        except Exception as e:
            error_result = {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

            if self.debug:
                print(f"🔧 [GLANCE_DEBUG] Check failed: {error_result}")

            return error_result

    def _analyze_images(self, images):
        """
        Analyze Glance images by status.

        Args:
            images: List of Glance image objects from OpenStack

        Returns:
            Dictionary containing image statistics organized by status,
            plus a list of problem images (status == killed)
        """
        stats = {
            'total': len(images),
            'by_status': {},
            'problem_images': []
        }

        for image in images:
            status = getattr(image, 'status', 'unknown')

            if status not in stats['by_status']:
                stats['by_status'][status] = 0
            stats['by_status'][status] += 1

            if status in self.PROBLEM_STATUSES:
                stats['problem_images'].append({
                    'id': getattr(image, 'id', 'unknown'),
                    'name': getattr(image, 'name', 'unnamed'),
                    'status': status
                })

        return stats

    def close_sessions(self):
        """Close OpenStack connection sessions to free resources."""
        if hasattr(self, 'conn'):
            self.conn.close()
            if self.debug:
                print(f"🔧 [GLANCE_DEBUG] Connections closed")